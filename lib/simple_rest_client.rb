require 'erb'
require 'uri'
require 'net/http'
require 'net/https'
require 'json'

# Base class to help easily create REST HTTP clients.
#
# Example client:
#   class ExampleAPI < SimpleRESTClient
#     def initialize
#       super(address: 'api.example.com')
#     end
#     def resource_list filter
#       get('/resource_list', query: {filter: filter}).body
#     end
#   end
# Alternatively, you can do it without making a child class:
#   require 'simple_rest_client'
#
#   class ExampleAPI
#     def initialize
#       @simple_rest_client = SimpleRESTClient.new(address: 'api.example.com')
#     end
#     def resource_list filter
#       @simple_rest_client.get('/resource_list', query: {filter: filter}).body
#     end
#   end
# You can define your own methods, regarding your own problem domain, to ease access to any resource in your API. Make use of any of the HTTP verb methods provided to easily interface with your API.
# TODO:
# * HTTP Status Code validation parameter.
# * Per request timeout
# * hooks: pre/post requests
# * String#force_encoding on Net::HTTPResponse#body and Net::HTTPResponse#read_body. https://bugs.ruby-lang.org/issues/2567
# * High level JSON methods
# * Logging support through hooks
# * Pagination aid support.
# * Better exceptions (inform connection, request and response information)
# * follow redirects.
# * Builder pattern for #initialize
# * retries.
class SimpleRESTClient

  # Default value for #net_http_start_opt.
  DEFAULT_NET_HTTP_START_OPT = {
    open_timeout: 5,
    read_timeout: 30,
    ssl_timeout:  10,
  }.freeze

  # Hostname or IP address of the server.
  attr_reader :address
  # Port of the server. Defaults to 80 if HTTP and 443 if HTTPS (depends on <tt>net_http_start_opt[:use_ssl] == true</tt>).
  attr_reader :port
  # Base path to prefix all requests with. Must be URL encoded when needed.
  attr_reader :base_path
  # Base query string to use in all requests. Must be provided as a Hash.
  attr_reader :base_query
  # Base headers to be used in all requests. Must be provided as a Hash.
  attr_reader :base_headers
  # Hash opt to be used with with Net::HTTP.start. Defaults to DEFAULT_NET_HTTP_START_OPT. If #port is 443 and :use_ssl is not specified, it will be set to true.
  attr_reader :net_http_start_opt
  # Username for basic auth.
  attr_reader :username
  # Password for basic auth.
  attr_reader :password

  # Creates a new HTTP client. Please refer to each attribute's documentation for details and default values.
  def initialize(
    address:            ,
    port:               nil,
    base_path:          nil,
    base_query:         {},
    base_headers:       {},
    net_http_start_opt: DEFAULT_NET_HTTP_START_OPT.dup,
    username:           nil,
    password:           nil
    )
    @address            = address
    @port               = if port
                          port
                        else
                          net_http_start_opt[:use_ssl] ? 443 : 80
                        end
    @base_path          = base_path
    @base_query         = base_query
    @base_headers       = base_headers
    @net_http_start_opt = net_http_start_opt
    unless @net_http_start_opt.has_key?(:use_ssl)
      @net_http_start_opt[:use_ssl] = true if port == 443
    end
    @username           = username
    @password           = password
    @net_http           = nil
  end

  # Define a instance method for given HTTP request method.
  def self.http_method http_method # :nodoc:
    self.class_eval do
      define_method(http_method) do |*args, &block|
        request(http_method, *args, &block)
      end
    end
  end

  # :section: RFC7231 Hypertext Transfer Protocol (HTTP/1.1): Semantics and Content

  ##
  # :method: get
  http_method :get

  ##
  # :method: head
  http_method :head

  ##
  # :method: post
  http_method :post

  ##
  # :method: put
  http_method :put

  ##
  # :method: delete
  http_method :delete

  ##
  # :method: options
  http_method :options

  ##
  # :method: trace
  http_method :trace

  # :section: RFC5789 PATCH Method for HTTP

  ##
  # :method: patch
  http_method :patch

  # :section: Generic requests

  # Performs a generic HTTP method request.
  # Body argument must only be used with methods that support sending a body.
  # request(http_method, path, query: {}, headers: {}, body: nil) {|response| ... } -> block return value
  # request(http_method, path, query: {}, headers: {}, body: nil) -> Net::HTTPResponse
  def request http_method, path, query: {}, headers: {}, body: nil
    uri = build_uri(path, query)
    request = build_request(http_method, uri, headers, body)
    response = net_http.request(request)
    if block_given?
      return (yield response)
    else
      return response
    end
  end

  private

  # Returns a cached instance of Net::HTTP.
  def net_http
    return @net_http if @net_http
    @net_http = Net::HTTP.start(address, port)
    ObjectSpace.define_finalizer( self, proc { @net_http.finish } )
    @net_http
  end

  def build_uri path='/', query={}
    # Base
    build_args = {
      host: address,
      port: port,
      path: "#{base_path}/#{path}".gsub(/\/+/, '/'),
    }
    # Basic Auth
    build_args.merge!(
      userinfo: "#{ERB::Util.url_encode(username)}:#{ERB::Util.url_encode(password.to_s)}",
    ) if username
    # Query
    conflicting_query_keys = (base_query.keys & query.keys)
    unless conflicting_query_keys.empty?
      raise ArgumentError, "Passed query parameters conflict with base_query parameters: #{conflicting_query_keys.join(', ')}."
    end
    merged_query = base_query.merge(query)
    build_args.merge!(
      query: URI.encode_www_form(merged_query),
    ) unless merged_query.empty?
    # Build
    ( net_http_start_opt[:use_ssl] ? URI::HTTPS : URI::HTTP ).build(build_args)
  end

  def build_request http_method, uri, headers, body
    begin
      request_class = Net::HTTP.const_get(http_method.downcase.capitalize)
    rescue NameError
      raise ArgumentError, "Unknown HTTP method named #{http_method}!"
    end
    if !request_class.const_get(:REQUEST_HAS_BODY) && body
      raise ArgumentError.new("unknown keyword: body")
    end
    request = request_class.new(
      uri,
      build_headers(headers)
    )
    request.basic_auth(username, password.to_s) if username
    request.body = body if body
    request
  end

  def build_headers headers
    conflicting_header_keys = base_headers.keys & headers.keys
    unless conflicting_header_keys.empty?
      raise ArgumentError, "Passed headers conflict with base_headers: #{conflicting_header_keys.join(', ')}."
    end
    base_headers
      .merge(headers)
      .map{|k,v| [k.to_s, v.to_s]}
      .to_h
  end

end
