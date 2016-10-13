require 'simple_rest_client'

class JSONServer < SimpleRESTClient
  def initialize
    super(
      address: 'jsonplaceholder.typicode.com',
      logger:  Logger.new(STDERR)
    )
  end

  class Post < SimpleRESTClient::Resource
    action :delete do
      verb :delete
      handler(204) { }
    end

    action :comment do
      verb :post
      path '/comments'
      headers(content_type: 'application/json')
      body do |attributes|
        JSON.dump(
          post_id: self[:id],
          text:    attributes[:text]
        )
      end
      handler(status_code: 202) do |response|
        id = JSON.parse(response.body)[:id]
        Comment.new(self, base_path: "/comments/#{id}")
      end
    end
  end

  namespace :posts do
    path '/posts'

    action :all do
      verb :get
      handler(
        status_code:  200,
        content_type: 'application/json'
      ) do |response|
        JSON.parse(response.body).each do |post|
          Post.new(self, base_path: post[:id].to_s)
        end
      end
    end

    action :create do |attributes|
      verb :post
      headers(content_type: 'application/json')
      body do
        JSON.dump(
          title: attributes[:title],
          text:  attributes[:text]
        )
      end
      handler(status_code: 202) do |response|
        id = JSON.parse(response.body)[:id]
        Post.new(self, base_path: id.to_s)
      end
    end
  end
enda
