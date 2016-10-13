# frozen_string_literal: true
require_relative '../lib/simple_rest_client'
require 'logger'
class SimpleRESTClient::Resource
  attr_reader :simple_rest_client
  attr_reader :attrs
  def initialize(simple_rest_client, attrs)
    @simple_rest_client = simple_rest_client
    @attrs              = attrs
  end

  def [](key)
    attrs[key.to_s]
  end

  def to_s
    attrs.to_s
  end
end

class JSONPlaceholder < SimpleRESTClient
  def initialize
    super(
      address: 'jsonplaceholder.typicode.com',
      logger: Logger.new(STDERR)
    )
  end

  class Post < SimpleRESTClient::Resource
    def to_s
      self[:title]
    end
  end

  def posts
    return to_enum(__method__) unless block_given?
    get_json('/posts').each do |attrs|
      yield Post.new(self, attrs)
    end
  end
end

require 'awesome_print'
c = JSONPlaceholder.new
c.get('/posts/1')

# !> I, [2016-05-02T22:42:01.486768 #28083]  INFO -- : GET http://jsonplaceholder.typicode.com/posts/1
