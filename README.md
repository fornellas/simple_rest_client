# Simple REST Client

Gem to aid construction of [REST](https://en.wikipedia.org/wiki/Representational_state_transfer) API gateway classes.

## Usage

### Construction

It can be used as a stand alone object:

```ruby
require 'simple_rest_client'
json_placeholder = SimpleRESTClient.new(
  address: 'jsonplaceholder.typicode.com',
)
json_placeholder.get('/users/1').body
```

Or as a base class:

```ruby
require 'simple_rest_client'
class JSONPlaceholder < SimpleRESTClient
  def initialize
    super(
      address: 'jsonplaceholder.typicode.com',
    )
  end
  def users
    get('/users').body
  end
end
json_placeholder = JSONPlaceholder.new
json_placeholder.users
```

Note that you can alternatively use the builder pattern with the constructor (useful for complex scenarios):

```ruby
SimpleRESTClient.new(address: 'jsonplaceholder.typicode.com') do |c|
  c.base_path = '/v1'
  c.username  = 'username'
  c.password  = 'password'
)
```

##### Base request parameters

Many APIs have common attributes to all URIs / requests. You can set up those with:

```ruby
SimpleRESTClient.new(
  address: 'example.com',
  base_path: '/api/v1', # Prefix URLs
  base_query: {token: 'PHEEPHEEVI2IOTOHTHEI'}, # Useful for authorization
  base_headers: {authorization: 'PHEEPHEEVI2IOTOHTHEI'}, # Also useful for authorization
)
```

##### Net::HTTP attributes

You can costumize any Net::HTTP attributes:

```ruby
SimpleRESTClient.new(
  address: 'example.com',
  net_http_attrs: {
    open_timeout: 1,
    read_timeout: 5,
    ssl_timeout:  5,
  }
)
```

##### Authentication

Basic Auth can be set up with:

```ruby
SimpleRESTClient.new(
  address:  'example.com',
  username: 'john',
  password: 'secret',
)
```

Many APIs do authentication via a token, passed either via a query string, or a header. You can use <tt>:base_path</tt> and <tt>:base_headers</tt> for that cases.

##### Logging

Minimum logging support is also implemented:

```ruby
require 'logger'
simple_rest_client = SimpleRESTClient.new(
  address:  'jsonplaceholder.typicode.com',
  logger: Logger.new(STDERR)
)
simple_rest_client.get('/posts/1')
# !> I, [2016-05-02T22:42:01.486768 #28083]  INFO -- : GET http://jsonplaceholder.typicode.com/posts/1
```

##### Hooks

You can implement the [observer pattern](https://en.wikipedia.org/wiki/Observer_pattern) with hooks:

```ruby
SimpleRESTClient.new(address: 'example.com') do |c|
  # Before
  c.add_pre_request_hook do |request|
    puts "Performing request #{request}..."
  end
  # After
  c.add_post_request_hook do |response, request|
    puts "Finished request #{request}, got response #{response}!"
  end
  # Around
  c.add_around_request_hook do |block, request|
    puts "Performing request #{request}..."
    response = block.call
    puts "Finished request #{request}, got response #{response}!"
  end
end
```

## Performing Requests

You can perform a request by invoking a method with the same name of the HTTP method. Examples:

```ruby
simple_rest_client.get('/posts/1')
simple_rest_client.put('/posts/1', body: 'text')
```

Without a block, requests will always return a Net::HTTPResponse object.

If you do requests with a block, the response will be yielded to it:

```ruby
simple_rest_client.get('/posts') do |response|
  # Process response here (eg: stream response body)
end
```

#### Sending streamed body

You can stream bodies just as you'd do with Net::HTTP:

```ruby
File.open('big_file', 'r') do |io|
  simple_rest_client.post(
    '/upload',
    body_stream: io
  )
end
```

#### Setting per request Net::HTTP attributes

Sometimes it is useful to set up Net::HTTP attributes per request (eg: increased timeout only for a particular request):

```ruby
simple_rest_client.get(
  '/posts',
  net_http_attrs: {
    read_timeout: 300,
  }
)
```

## Design Principles

There are plenty of alternatives to help interfacing with a REST API in Ruby, and many work just fine. This Gem is an attempt distinguish itself, by uniting some known patterns, do the best to not get in your way, have sensible defaults and useful common functionality.

* Use Ruby's [idioms](https://en.wikipedia.org/wiki/Programming_idiom) whenever possible.
* Use known [design patterns](https://en.wikipedia.org/wiki/Software_design_pattern).
* Prefer [convention over configuration](https://en.wikipedia.org/wiki/Convention_over_configuration).
  * Usual cases should work of the shelf.
* Single thread over multi-thread concurrent code.
  * Lower code complexity.
  * Use [thread local](https://en.wikipedia.org/wiki/Thread-local_storage) objects for multi-thrad environments.
* Use persistent connection, but no connection pool.
  * Lower code complexity.
  * More resilience.
  * Query throughput.
* Provide "low level" HTTP methods access as well "high level" abstractions (eg: internal JSON parsing).
* Aid pagination though an Enumerable object.
* Avoid [dependency hell](https://en.wikipedia.org/wiki/Dependency_hell) pitfalls.
  * No fancy dependencies, use Ruby's standard libraries.
  * Respect [Semantic Versioning](http://semver.org/), with a twist: when there is an incompatible API change, create a Gem with a new name, to allow one to use in the same project, both previous and a newer version.
* Do not use class level client configuration, instead, use instance level configuration, allowing connection to the same API but with different credentials for example.
* Meaningful exceptions with useful informative messages to ease debugging.
  * Inform FQDN, ip address, port, HTTP methdod etc.
* Test everything.
* Document everything.
