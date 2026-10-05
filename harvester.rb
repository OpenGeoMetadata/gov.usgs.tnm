require 'date'
require 'fileutils'
require 'json'
require 'set'
require_relative 'bucket'
require_relative 'catalog'
require_relative 'datasets'
require_relative 'extents'
require_relative 'http_client'
require_relative 'mapper'
require_relative 'package'

# Regenerates the Aardvark records in metadata-aardvark/ from The National Map's catalog of its vector data,
# checked against what's actually on its download server, and logs records that leave the repository in
# withdrawn.json.
#
# The catalog lists every product on every run, so there is no incremental state to keep: each run rebuilds every
# record and writes only the files whose contents changed, and an unchanged catalog leaves the repository
# untouched. What each run fetched is kept in tmp/snapshot, so it can be rerun offline with SOURCE=tmp/snapshot.
class Harvester
  METADATA_DIR = 'metadata-aardvark'
  WITHDRAWN_FILE = 'withdrawn.json'
  SNAPSHOT_DIR = 'tmp/snapshot'

  WITHDRAWALS_SCHEMA = 'https://opengeometadata.org/schema/ogm-withdrawals-1.0.json'

  # Refuse to withdraw anything if a run would shrink the repository by more than this fraction, so that a
  # truncated or broken catalog can't empty it. Rerun with FORCE=1 when the drop is real.
  MAX_SHRINK = 0.02

  # A pause between requests to each host, in seconds: the API is asked about 210 times a run, and the bucket
  # listed about 650 times
  INTERVALS = { 'tnmaccess.nationalmap.gov' => 0.5, Bucket::HOST => 0.1 }.freeze

  class Error < StandardError; end

  def self.run(**options)
    new(**options).run
  end

  # Records are filed by dataset, and the datasets with thousands of packages are bucketed further, which keeps
  # every directory under GitHub's 1,000-entry listing limit: quadrangles by the thousands of their GNIS cell, NHD's
  # hydrologic units by region, and contour tiles by state. A record's path follows from its id.
  def self.directories(id)
    slug, rest = id.delete_prefix(Package::ID_PREFIX).split('-', 2)
    case slug
    when 'vector' then [slug, rest.match?(/\A\d+\z/) ? (rest.to_i / 1000).to_s : rest.split('-').first]
    when 'nhd' then (region = rest[/\Ahu\d-(\d{2})/, 1]) ? [slug, region] : [slug]
    when 'contours' then rest == 'national' ? [slug] : [slug, rest.split('-').first]
    else [slug]
    end
  end

  attr_reader :source, :metadata_dir, :withdrawn_file, :snapshot_dir, :dry_run, :force, :max_shrink, :today, :log

  def initialize(source: nil, metadata_dir: METADATA_DIR, withdrawn_file: WITHDRAWN_FILE, snapshot_dir: SNAPSHOT_DIR,
                 dry_run: false, force: false, max_shrink: MAX_SHRINK, today: Date.today, log: $stdout, http: nil)
    @source = source
    @metadata_dir = metadata_dir
    @withdrawn_file = withdrawn_file
    @snapshot_dir = snapshot_dir
    @dry_run = dry_run
    @force = force
    @max_shrink = max_shrink
    @today = today
    @log = log
    @http = http
  end

  # @return [Hash] counts of what the run did
  def run
    catalog, bucket = sources
    packages = Package.group(catalog.products, log: log).map { |package| package.resolve(bucket) }
    circling = Extents.correct(packages.select(&:available?))
    check_complete(packages)
    counts = Hash.new(0)
    published = publishable(packages, counts)
    existing = existing_records
    check_shrinkage(existing.size, published.size)

    shared_titles = shared_titles(published)
    published.each do |package|
      record = Mapper.map(package, distinguish: shared_titles.include?(title_key(package)))
      counts[write_json(record_path(package.id), record)] += 1
    end
    collections = write_collections(published, counts)
    unavailable = packages.reject(&:available?).to_h { |package| [package.id, package] }
    counts.merge!(withdraw(removals(existing, published, unavailable), published.map(&:id).to_set | collections))

    report(catalog, bucket, published, counts)
    report_circling(circling)
    counts
  end

  private

  def sources
    return [Catalog.load(source), Bucket.load(source)] if source

    http = @http || HttpClient.new(interval: INTERVALS)
    catalog = Catalog.fetch(http: http, log: log)
    bucket = Bucket.fetch(catalog.urls, downloads: catalog.download_urls, http: http, log: log)
    catalog.save(snapshot_dir)
    bucket.save(snapshot_dir)
    [catalog, bucket]
  end

  # A dataset the catalog says nothing about means the catalog came back broken, not that USGS withdrew it
  def check_complete(packages)
    present = packages.map { |package| package.dataset.slug }.to_set
    missing = Datasets::ALL.reject { |dataset| present.include?(dataset.slug) }
    return if missing.empty? || force

    raise Error, "The catalog lists nothing for #{missing.map(&:name).join(', ')}. Nothing was changed; rerun with " \
                 'FORCE=1 if that is real.'
  end

  # The packages that can become records: those with files left to download and an extent to place them by. Two
  # packages can only share an id if USGS renamed a quadrangle and left the old files behind, so the one published
  # last is kept.
  def publishable(packages, counts)
    available = packages.select(&:available?)
    counts[:unavailable] = packages.size - available.size
    placed = available.select(&:bounds)
    counts[:without_extent] = available.size - placed.size
    placed.group_by(&:id).map do |_id, namesakes|
      counts[:namesakes] += namesakes.size - 1
      namesakes.max_by { |package| [package.published.to_s, package.downloads.size] }
    end
  end

  def check_shrinkage(existing_count, kept_count)
    return if force || existing_count.zero? || kept_count >= existing_count * (1 - max_shrink)

    raise Error, "This run would leave #{kept_count} records, down from #{existing_count}: more than " \
                 "#{(max_shrink * 100).round}% fewer. Nothing was changed; rerun with FORCE=1 if the drop is real."
  end

  # Packages of a dataset whose titles would be the same get their publication dates added to tell them apart
  def shared_titles(packages)
    packages.map { |package| title_key(package) }.tally.select { |_key, count| count > 1 }.keys.to_set
  end

  def title_key(package)
    [package.dataset.slug, Mapper.new(package).base_title]
  end

  def record_path(id)
    File.join(metadata_dir, *self.class.directories(id), "#{id}.json")
  end

  def collection_path(dataset)
    File.join(metadata_dir, dataset.slug, "#{Mapper.collection_id(dataset)}.json")
  end

  def collection_ids
    Datasets::ALL.map { |dataset| Mapper.collection_id(dataset) }.to_set
  end

  # Every package's record currently in the repository, by id
  def existing_records
    Dir.glob(File.join(metadata_dir, '**', "#{Package::ID_PREFIX}*.json")).to_h do |path|
      [File.basename(path, '.json'), path]
    end.reject { |id, _path| collection_ids.include?(id) }
  end

  # @return [Set] the ids of the collections written
  def write_collections(published, counts)
    published.group_by(&:dataset).to_h do |dataset, packages|
      status = write_json(collection_path(dataset), Mapper.collection(dataset, packages))
      counts[:"collections_#{status}"] += 1
      [Mapper.collection_id(dataset), status]
    end.keys.to_set
  end

  def write_json(path, data)
    write_file(path, "#{JSON.pretty_generate(data)}\n")
  end

  # Writes the file only when its contents change, so unchanged records don't show up in git
  # @return [Symbol] :created, :updated, or :unchanged
  def write_file(path, content)
    exists = File.exist?(path)
    return :unchanged if exists && File.read(path, mode: 'r:bom|utf-8') == content

    unless dry_run
      FileUtils.mkdir_p(File.dirname(path))
      File.write(path, content, mode: 'w:utf-8')
    end
    exists ? :updated : :created
  end

  # The records leaving the repository, each with its withdrawal entry and the file to delete
  def removals(existing, published, unavailable)
    ids = published.to_h { |package| [package.id, package] }
    (existing.keys - ids.keys).sort.map { |id| [withdrawal(id, ids, unavailable), existing[id]] }
  end

  # Records that leave the repository are deleted and logged in withdrawn.json, following the proposed
  # OpenGeoMetadata withdrawal convention: deleting a file alone doesn't tell harvesters to delete the record.
  # Entries are only ever removed for records that have come back.
  # @param published [Set] the id of every record the repository now has
  def withdraw(removals, published)
    withdrawals = read_withdrawals
    republished, entries = withdrawals['withdrawn'].partition { |entry| published.include?(entry['id']) }

    removals.each do |entry, path|
      entries = entries.reject { |other| other['id'] == entry['id'] } << entry
      File.delete(path) if !dry_run && File.exist?(path)
    end

    if !dry_run && (removals.any? || republished.any?)
      remove_empty_directories
      File.write(withdrawn_file, "#{JSON.pretty_generate(withdrawals.merge('withdrawn' => entries))}\n", mode: 'w:utf-8')
    end
    reasons = removals.map { |entry, _path| entry['reason'] }.tally
    { withdrawn: removals.size, without_files: reasons.fetch('quality', 0),
      superseded: reasons.fetch('superseded', 0), republished: republished.size }
  end

  def read_withdrawals
    return { '$schema' => WITHDRAWALS_SCHEMA, 'ogm_version' => '1.0', 'withdrawn' => [] } unless File.exist?(withdrawn_file)

    JSON.parse(File.read(withdrawn_file, mode: 'r:bom|utf-8'))
  end

  def withdrawal(id, published, unavailable)
    entry = { 'id' => id, 'date' => today.iso8601 }
    replacement = later_edition(id, published)
    if unavailable.key?(id)
      entry.merge('reason' => 'quality',
                  'note' => "The National Map still lists this package, but none of its files are on its download server.")
    elsif replacement
      entry.merge('reason' => 'superseded', 'note' => "USGS published a later edition, which has its own record.",
                  'is_replaced_by' => [replacement])
    else
      entry.merge('reason' => 'upstream-removed')
    end
  end

  # The record of a later edition of the same area, for the datasets whose editions are packages of their own:
  # 3DHP's, whose ids end in their dates
  def later_edition(id, published)
    stem, date = id.match(/\A(.+)-(\d{8})\z/)&.captures
    return nil unless stem

    published.keys.select { |other| other.start_with?("#{stem}-") && other.delete_prefix("#{stem}-") > date }.max
  end

  def remove_empty_directories
    Dir.glob(File.join(metadata_dir, '**', '*/')).sort_by { |dir| -dir.length }.each do |dir|
      Dir.rmdir(dir) if Dir.empty?(dir)
    end
  end

  def report(catalog, bucket, published, counts)
    log.puts "Catalog: #{catalog.products.size} products; bucket listing: #{bucket.size} objects"
    published.map { |package| package.dataset.slug }.tally.sort.each { |slug, count| log.puts "  #{slug}: #{count} packages" }
    log.puts "Records: #{counts[:created]} created, #{counts[:updated]} updated, #{counts[:unchanged]} unchanged; " \
             "collections: #{counts[:collections_created]} created, #{counts[:collections_updated]} updated, " \
             "#{counts[:collections_unchanged]} unchanged"
    log.puts "Skipped: #{counts[:unavailable]} packages with no files on the download server, " \
             "#{counts[:without_extent]} without an extent, #{counts[:namesakes]} older namesakes"
    log.puts "Withdrawn: #{counts[:withdrawn]} (#{counts[:without_files]} without files, #{counts[:superseded]} " \
             "superseded by a later edition); republished: #{counts[:republished]}"
    log.puts 'Dry run: nothing was written' if dry_run
  end

  # Packages whose box circles the globe for want of a better one, which `ruby extents.rb` can measure
  def report_circling(circling)
    return if circling.empty?

    log.puts "Extents: #{circling.size} packages' boxes circle the globe, and #{Extents::FILE} has no better one " \
             "for them; run `ruby extents.rb` to measure them: #{circling.map(&:id).sort.join(', ')}"
  end
end

if __FILE__ == $0
  # Report progress as it happens, rather than all at the end, when the log is a file or GitHub's
  $stdout.sync = true
  begin
    Harvester.run(source: ENV['SOURCE'].to_s.empty? ? nil : ENV['SOURCE'], dry_run: !ENV['DRY_RUN'].to_s.empty?,
                  force: !ENV['FORCE'].to_s.empty?)
  rescue Harvester::Error, Catalog::Error, Bucket::Error, Snapshot::Error, HttpClient::Error => e
    warn "Harvest stopped: #{e.message}"
    exit 1
  end
end
