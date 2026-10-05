require 'cgi'
require 'uri'
require_relative 'http_client'
require_relative 'snapshot'

# What's actually on The National Map's download server. Nearly every file is in USGS's prd-tnm S3 bucket, which
# can be listed, so the harvester lists the folders the catalog's files are in and reads each file's size from
# the listing. The catalog also lists files that are gone, and its own sizes are unreliable.
#
# The few files elsewhere (GNIS's 2017 gazetteer files) can't be listed, so they're checked one at a time.
class Bucket
  HOST = 'prd-tnm.s3.amazonaws.com'
  LIST_URL = "https://#{HOST}/"

  OBJECTS_FILE = 'bucket.jsonl'
  REMOTE_FILE = 'remote.jsonl'

  class Error < StandardError; end

  # The S3 key of a file on the bucket, or nil for a file elsewhere
  def self.key(url)
    uri = URI(url.to_s)
    uri.host == HOST ? URI.decode_uri_component(uri.path).delete_prefix('/') : nil
  rescue URI::InvalidURIError
    nil
  end

  def self.path(url)
    URI.decode_uri_component(URI(url.to_s).path)
  rescue URI::InvalidURIError
    url.to_s
  end

  # The folders to list for a set of URLs: the first three levels of each file's folder, e.g.
  # StagedProducts/Hydrography/NHD/
  def self.prefixes(urls)
    urls.filter_map { |url| key(url) }.map { |key| "#{File.dirname(key).split('/').first(3).join('/')}/" }.uniq.sort
  end

  # Lists the bucket under every folder the URLs are in, and checks the downloads elsewhere one by one
  # @param urls [Array<String>] every file the catalog links, for the folders to list
  # @param downloads [Array<String>] the files to check when they aren't on the bucket
  def self.fetch(urls, downloads: urls, http: HttpClient.new(interval: { HOST => 0.1 }), log: $stdout)
    prefixes = prefixes(urls)
    log.puts "Listing #{prefixes.size} folders of #{HOST}"
    objects = {}
    prefixes.each { |prefix| list(http, prefix) { |key, size| objects[key] = size } }

    remote = downloads.reject { |url| key(url) }.uniq.sort
    log.puts "Checking #{remote.size} files elsewhere" if remote.any?
    new(objects, remote.to_h { |url| [url, check(http, url)] })
  end

  def self.list(http, prefix)
    token = nil
    loop do
      query = { 'list-type' => '2', 'prefix' => prefix, 'max-keys' => '1000' }
      query['continuation-token'] = token if token
      response = http.get("#{LIST_URL}?#{URI.encode_www_form(query)}")
      # Net::HTTP hands back bytes; keys with accented names only match the catalog's URLs as UTF-8
      body = response.body.to_s.dup.force_encoding(Encoding::UTF_8)
      raise Error, "Listing #{prefix} failed: #{response.code} #{body[0, 200]}" unless response.is_a?(Net::HTTPSuccess)

      body.scan(%r{<Contents>(.*?)</Contents>}m) do |(contents)|
        yield CGI.unescapeHTML(contents[%r{<Key>(.*?)</Key>}m, 1]), contents[%r{<Size>(\d+)</Size>}, 1].to_i
      end
      return unless body.include?('<IsTruncated>true</IsTruncated>')

      token = CGI.unescapeHTML(body[%r{<NextContinuationToken>(.*?)</NextContinuationToken>}m, 1].to_s)
      raise Error, "Listing #{prefix} was truncated without a continuation token" if token.empty?
    end
  end

  # @return [Array(Boolean, Integer)] whether the file is there, and its size if the server says. A 404 or 410
  # counts as gone, and so does a redirect to anything but the same file: geonames.usgs.gov answers for its
  # retired files by sending readers to the Board on Geographic Names' home page. A server that can't be reached
  # today says nothing about whether the file still exists, so it counts as there.
  def self.check(http, url, redirects: 3)
    response = http.head(url)
    return [false, nil] if %w[404 410].include?(response.code)

    if response.is_a?(Net::HTTPRedirection)
      location = URI.join(url, response['Location'].to_s).to_s
      same_file = File.basename(path(location)) == File.basename(path(url))
      return same_file && redirects.positive? ? check(http, location, redirects: redirects - 1) : [false, nil]
    end

    length = response['Content-Length']
    [true, response.is_a?(Net::HTTPSuccess) && length ? length.to_i : nil]
  rescue HttpClient::Error
    [true, nil]
  end

  def self.load(dir)
    objects = Snapshot.read(dir, OBJECTS_FILE).to_h { |key, size| [key, size] }
    remote = Snapshot.read(dir, REMOTE_FILE).to_h { |url, available, size| [url, [available, size]] }
    new(objects, remote)
  end

  # @param objects [Hash{String => Integer}] every listed object's size, by key
  # @param remote [Hash{String => Array}] [available, size] for each file elsewhere
  def initialize(objects, remote = {})
    @objects = objects
    @remote = remote
  end

  def size
    @objects.size
  end

  # @return [Array(Boolean, Integer)] whether the file is there, and its size if known. A file elsewhere that
  # wasn't checked is assumed to be there.
  def file(url)
    key = self.class.key(url)
    return @remote.fetch(url, [true, nil]) unless key

    size = @objects[key]
    [!size.nil?, size]
  end

  def save(dir)
    Snapshot.write(dir, OBJECTS_FILE, @objects.sort.map { |key, size| [key, size] })
    Snapshot.write(dir, REMOTE_FILE, @remote.sort.map { |url, (available, size)| [url, available, size] })
  end
end
