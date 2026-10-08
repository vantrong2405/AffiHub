# frozen_string_literal: true

require "ipaddr"
require "resolv"
require "socket"
require "timeout"
require "uri"

class SourceAssets::DownloadEgressProxy
  CONFIGURATION = Rails.application.config_for(:video_workflow)
    .deep_symbolize_keys
    .fetch(:source_download)
  BLOCKED_IP_RANGES = CONFIGURATION.fetch(:blocked_ip_ranges).map { |range| IPAddr.new(range) }
  MAX_REQUEST_LINE_BYTES = 4096
  MAX_HEADER_BYTES = 8192
  BUFFER_BYTES = 16_384

  class BlockedDestination < StandardError
  end

  # Starts a loopback-only HTTP CONNECT proxy for a single download worker.
  #
  # @return [String] the local proxy URL passed to the downloader
  def start
    raise IOError, "proxy already running" if @server

    @connections = []
    @connections_lock = Mutex.new
    @server = TCPServer.new(CONFIGURATION.fetch(:proxy_bind_host), 0)
    @accept_thread = Thread.new { step_accept_connections }
    "http://#{CONFIGURATION.fetch(:proxy_bind_host)}:#{@server.addr[1]}"
  end

  # Stops the local listener and closes active proxy tunnels.
  #
  # @return [nil] after all proxy resources have been closed
  def stop
    @server&.close
    @connections_lock&.synchronize { @connections.each { |connection| connection.close rescue IOError } }
    @accept_thread&.join(1)
    @server = nil
    nil
  end

  # Validates a source URL and resolves all of its addresses without connecting.
  #
  # @param url [String] the source URL to validate before enqueueing
  # @return [Boolean] true when every resolved address is public and allowlisted
  def validate_url(url:)
    uri = step_validate_destination(url)
    step_resolve_public_addresses(uri.host)
    true
  end

  # Opens a socket to one validated public address without resolving the host again.
  #
  # @param url [String] the HTTPS URL from an initial request or redirect
  # @return [TCPSocket] the pinned upstream socket
  def open_upstream(url:)
    uri = step_validate_destination(url)
    address = step_resolve_public_addresses(uri.host).first
    Socket.tcp(address, uri.port, nil, connect_timeout: CONFIGURATION.fetch(:connect_timeout_seconds))
  rescue BlockedDestination
    raise
  rescue SocketError, SystemCallError, Timeout::Error
    raise BlockedDestination
  end

  private

  def step_accept_connections
    loop do
      client = @server.accept
      @connections_lock.synchronize { @connections << client }
      Thread.new(client) do |connection|
        step_serve_client(connection)
      ensure
        @connections_lock.synchronize { @connections.delete(connection) }
        connection.close unless connection.closed?
      end
    end
  rescue IOError, Errno::EBADF
    nil
  end

  def step_serve_client(client)
    upstream = nil
    target = step_read_connect_target(client)
    upstream = open_upstream(url: target)
    client.write("HTTP/1.1 200 Connection Established\r\n\r\n")
    step_tunnel(client, upstream)
  rescue BlockedDestination
    client.write("HTTP/1.1 403 Forbidden\r\nConnection: close\r\n\r\n")
  rescue IOError, SystemCallError, URI::InvalidURIError
    client.write("HTTP/1.1 400 Bad Request\r\nConnection: close\r\n\r\n")
  ensure
    upstream&.close unless upstream&.closed?
  end

  def step_read_connect_target(client)
    request_line = client.gets("\r\n", MAX_REQUEST_LINE_BYTES)
    match = request_line.to_s.match(/\ACONNECT (\[[0-9a-f:]+\]:\d+|[^:\s]+:\d+) HTTP\/1\.[01]\r\n\z/i)
    raise BlockedDestination unless match

    header_bytes = 0
    loop do
      header = client.gets("\r\n", MAX_REQUEST_LINE_BYTES)
      raise BlockedDestination unless header
      break if header == "\r\n"

      header_bytes += header.bytesize
      raise BlockedDestination if header_bytes > MAX_HEADER_BYTES
    end

    "https://#{match[1]}/"
  end

  def step_tunnel(client, upstream)
    loop do
      readable, = IO.select([ client, upstream ])
      readable.each do |source|
        payload = source.read_nonblock(BUFFER_BYTES, exception: false)
        return if payload.nil?
        next if payload == :wait_readable

        destination = source.equal?(client) ? upstream : client
        destination.write(payload)
      end
    end
  rescue IOError, SystemCallError
    nil
  end

  def step_validate_destination(url)
    uri = URI.parse(url.to_s)
    host = uri.host.to_s.downcase.delete_suffix(".")
    valid_url = uri.scheme == "https" && uri.port == 443 && uri.userinfo.nil? && step_allowed_host?(host)
    raise BlockedDestination unless valid_url

    uri
  rescue URI::InvalidURIError
    raise BlockedDestination
  end

  def step_allowed_host?(host)
    CONFIGURATION.fetch(:allowed_hosts).any? do |domain|
      host == domain || host.end_with?(".#{domain}")
    end
  end

  def step_resolve_public_addresses(host)
    addresses = Resolv.getaddresses(host).uniq
    raise BlockedDestination if addresses.empty?

    parsed_addresses = addresses.map { |address| IPAddr.new(address) }
    raise BlockedDestination if parsed_addresses.any? { |address| step_blocked_address?(address) }

    addresses
  rescue IPAddr::InvalidAddressError, Resolv::ResolvError
    raise BlockedDestination
  end

  def step_blocked_address?(address)
    BLOCKED_IP_RANGES.any? { |network| network.include?(address) }
  end
end
