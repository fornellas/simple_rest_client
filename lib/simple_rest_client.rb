require 'erb'
require 'uri'
require 'net/http'
require 'net/https'
require 'json'

# Base class do help easily create REST HTTP clients.
#
# Example client:
#   class ExampleAPI < SimpleRESTClient
#     def initialize
#       super(address: 'api.example.com')
#     end
#     def resource_list query
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
#     def resource_list query
#       @simple_rest_client.get('/resource_list', query: {filter: filter}).body
#     end
#   end
# You can define your own methods, regarding your own problem domain, to ease access to any resource in your API. Make use of any of the HTTP verb methods provided to easily interface with your API.
#
# For all HTTP verb methods, if no block is given, the default is to validate the response with DEFAULT_RESPONSE_VALIDATOR.
#
# TODO: String#force_encoding on Net::HTTPResponse#body and Net::HTTPResponse#read_body.
#
# TODO: Better exceptions (inform connection, request and response information)
#
# TODO: Logging support
#
# TODO: follow redirects.
#
# TODO: retries.
class SimpleRESTClient

  # Default value for #net_http_start_opt.
  DEFAULT_NET_HTTP_START_OPT = {
    open_timeout: 5,
    read_timeout: 30,
    ssl_timeout:  10,
  }.freeze

  # Default validator used for any HTTP request. It will raise an exception unless the response is a Net::HTTPSuccess.
  DEFAULT_RESPONSE_VALIDATOR = lambda do |response|
    unless response.is_a? Net::HTTPSuccess
      raise "HTTP request no successfull"
    end
  end.freeze

  # Hostname or IP address of the server.
  attr_reader :address
  # Port of the server. Defaults to 80 if HTTP and 443 if HTTPS.
  attr_reader :port
  # Base path to prefix all requests with. Must be URL encoded when needed.
  attr_reader :base_path
  # Base query string to use in all requests. Must be provided as a Hash.
  attr_reader :base_query
  # Base headers to be used in all requests. Must be provided as a Hash.
  attr_reader :base_headers
  # Hash opt to be used with with Net::HTTP.start.
  attr_reader :net_http_start_opt
  # Username for basic auth.
  attr_reader :username
  # Password for basic auth.
  attr_reader :password

  # Creates a new HTTP client. Please refer to each attribute's documentation for details.
  def initialize(
    address:            ,
    port:               nil,
    base_path:          nil,
    base_query:         {},
    base_headers:       {},
    net_http_start_opt: DEFAULT_NET_HTTP_START_OPT,
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
    @username           = username
    @password           = password
    @net_http           = nil
  end


  # :section: High level metdos

  # Makes a request and return its parsed JSON body. Will raise an exception if either the request was not successfull, the response has no body or its Content-Type is not <tt>application/json</tt>.
  # :call-seq:
  # get_json(path, query: {}, headers: {}) -> Hash
  def get_json *args
    get(*args) do |response|
      DEFAULT_RESPONSE_VALIDATOR.call(response)
      unless response.class.const_get(:HAS_BODY)
        raise "Response has no body"
      end
      unless response.content_type == 'application/json'
        raise "Response Content-Type is not application/json"
      end
      JSON.parse(response.body)
    end
  end

  def self.http_method_send_json name # :nodoc:
    self.class_eval do
      define_method(:"#{name}_json") do |path, query: {}, headers: {}, body:|
        serialized_body = JSON.generate(body)
        send(
          name,
          path,
          query:    query,
          headers: headers.merge(
            'Content-Type' => "application/json;charset=#{serialized_body.encoding.to_s.downcase}",
          ),
          body: serialized_body,
        )
      end
    end
  end

  ##
  # :method:
  # Makes a POST request. body will be serialized with JSON.generate, and Content-Type header will be set.
  # :call-seq:
  # post_json(path, query: {}, headers: {}, body:) -> Net::HTTPResponse
  http_method_send_json :post

  ##
  # :method:
  # Makes a PUT request. body will be serialized with JSON.generate, and Content-Type header will be set.
  # :call-seq:
  # put_json(path, query: {}, headers: {}, body:) -> Net::HTTPResponse
  http_method_send_json :put

  ##
  # :method:
  # Makes a PATCH request. body will be serialized with JSON.generate, and Content-Type header will be set.
  # :call-seq:
  # patch_json(path, query: {}, headers: {}, body:) -> Net::HTTPResponse
  http_method_send_json :patch

  # Define a instance method for given HTTP verb name.
  def self.http_method name # :nodoc:
    self.class_eval do
      define_method(name) do |*args, &block|
        net_http_request(name, *args, &block)
      end
    end
  end

  # :section: HTTP verbs

  ##
  # :method: get
  # :call-seq:
  # get(path, query: {}, headers: {}) {|response| ... } -> block return value
  # get(path, query: {}, headers: {}) -> Net::HTTPResponse
  http_method :get

  ##
  # :method: head
  # :call-seq:
  # head(path, query: {}, headers: {}) {|response| ... } -> block return value
  # head(path, query: {}, headers: {}) -> Net::HTTPResponse
  http_method :head

  ##
  # :method: delete
  # :call-seq:
  # delete(path, query: {}, headers: {}) {|response| ... } -> block return value
  # delete(path, query: {}, headers: {}) -> Net::HTTPResponse
  http_method :delete

  ##
  # :method: options
  # :call-seq:
  # options(path, query: {}, headers: {}) {|response| ... } -> block return value
  # options(path, query: {}, headers: {}) -> Net::HTTPResponse
  http_method :options

  ##
  # :method: trace
  # :call-seq:
  # trace(path, query: {}, headers: {}) {|response| ... } -> block return value
  # trace(path, query: {}, headers: {}) -> Net::HTTPResponse
  http_method :trace

  ##
  # :method: copy
  # :call-seq:
  # copy(path, query: {}, headers: {}) {|response| ... } -> block return value
  # copy(path, query: {}, headers: {}) -> Net::HTTPResponse
  http_method :copy

  ##
  # :method: move
  # :call-seq:
  # move(path, query: {}, headers: {}) {|response| ... } -> block return value
  # move(path, query: {}, headers: {}) -> Net::HTTPResponse
  http_method :move

  ##
  # :method: post
  # :call-seq:
  # post(path, query: {}, headers: {}, body: nil) {|response| ... } -> block return value
  # post(path, query: {}, headers: {}, body: nil) -> Net::HTTPResponse
  http_method :post

  ##
  # :method: put
  # :call-seq:
  # put(path, query: {}, headers: {}, body: nil) {|response| ... } -> block return value
  # put(path, query: {}, headers: {}, body: nil) -> Net::HTTPResponse
  http_method :put

  ##
  # :method: patch
  # :call-seq:
  # patch(path, query: {}, headers: {}, body: nil) {|response| ... } -> block return value
  # patch(path, query: {}, headers: {}, body: nil) -> Net::HTTPResponse
  http_method :patch

  ##
  # :method: propfind
  # :call-seq:
  # propfind(path, query: {}, headers: {}, body: nil) {|response| ... } -> block return value
  # propfind(path, query: {}, headers: {}, body: nil) -> Net::HTTPResponse
  http_method :propfind

  ##
  # :method: proppatch
  # :call-seq:
  # proppatch(path, query: {}, headers: {}, body: nil) {|response| ... } -> block return value
  # proppatch(path, query: {}, headers: {}, body: nil) -> Net::HTTPResponse
  http_method :proppatch

  ##
  # :method: mkcol
  # :call-seq:
  # mkcol(path, query: {}, headers: {}, body: nil) {|response| ... } -> block return value
  # mkcol(path, query: {}, headers: {}, body: nil) -> Net::HTTPResponse
  http_method :mkcol

  ##
  # :method: lock
  # :call-seq:
  # lock(path, query: {}, headers: {}, body: nil) {|response| ... } -> block return value
  # lock(path, query: {}, headers: {}, body: nil) -> Net::HTTPResponse
  http_method :lock

  ##
  # :method: unlock
  # :call-seq:
  # unlock(path, query: {}, headers: {}, body: nil) {|response| ... } -> block return value
  # unlock(path, query: {}, headers: {}, body: nil) -> Net::HTTPResponse
  http_method :unlock

  private

  # Returns a cached instance of Net::HTTP.
  def net_http
    return @net_http if @net_http
    @net_http = Net::HTTP.start(address, port)
    ObjectSpace.define_finalizer( self, proc { @net_http.finish } )
    @net_http
  end

  def build_uri path='/', query={}
    build_args = {
      host: address,
      port: port,
      path: "#{base_path}/#{path}".gsub(/\/+/, '/'),
    }
    build_args.merge!(
      userinfo: "#{ERB::Util.url_encode(username)}:#{ERB::Util.url_encode(password.to_s)}",
    ) if username
    merged_query = base_query.merge(query)
    build_args.merge!(
      query: URI.encode_www_form(merged_query),
    ) unless merged_query.empty?
    ( net_http_start_opt[:use_ssl] ? URI::HTTPS : URI::HTTP ).build(build_args)
  end

  def build_request method, uri, headers, body
    request_class = Net::HTTP.const_get(method.downcase.capitalize)
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
    base_headers
      .merge(headers)
      .map{|k,v| [k.to_s, v.to_s]}
      .to_h
  end

  def net_http_request method, path, query: {}, headers: {}, body: nil
    uri = build_uri(path, query)
    request = build_request(method, uri, headers, body)
    # puts "#{method.to_s.upcase} #{uri}"
    # request.each do |key, value|
    #   puts "#{key}: #{value}"
    # end
    # puts
    # puts request.body
    response = net_http.request(request)
    if block_given?
      return (yield response)
    else
      DEFAULT_RESPONSE_VALIDATOR.call(response)
      return response
    end
  end

end
