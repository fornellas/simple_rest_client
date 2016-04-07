require 'simple_rest_client'

RSpec.describe SimpleRESTClient do
  let(:address) { 'example.com' }
  subject { described_class.new(address: address) }
  context '#initialize' do
    context '#port' do
      context 'defaults' do
        context 'HTTP' do
          subject do
            described_class.new(
            address: address,
            )
          end
          it 'is set to 80' do
            expect(subject.port).to eq(80)
          end
        end
        context 'HTTPS' do
          subject do
            described_class.new(
              address: address,
              net_http_start_opt: {
                use_ssl: true,
              }
            )
          end
          it 'is set to 443' do
            expect(subject.port).to eq(443)
          end
        end
      end
    end
    context '#net_http_start_opt' do
      context 'defaults' do
        context 'not specified' do
          it 'is set to DEFAULT_NET_HTTP_START_OPT' do
            expect(subject.net_http_start_opt).to eq(described_class.const_get(:DEFAULT_NET_HTTP_START_OPT))
          end
        end
        context 'port is 443' do
          let(:port) { 443 }
          context ':use_ssl not specified' do
            subject do
              described_class.new(
                address: address,
                port: port
              )
            end
            it 'sets :use_ssl' do
              expect(subject.net_http_start_opt[:use_ssl]).to eq(true)
            end
          end
          context ':use_ssl specified' do
            let(:use_ssl_value) { false }
            subject do
              described_class.new(
                address: address,
                port: port,
                net_http_start_opt: {
                  use_ssl: use_ssl_value
                }
              )
            end
            it 'keeps :use_ssl value' do
              expect(subject.net_http_start_opt[:use_ssl]).to eq(use_ssl_value)
            end
          end
        end
      end
    end
  end
  context '#base_path' do
    context 'unset' do
      it 'does requests without base_path prefix'
    end
    context 'set' do
      it 'prefix requests with base_path'
    end
  end
  context '#base_query' do
    context 'unset' do
      it 'does not change query'
    end
    context 'set' do
      context 'conflicting parameters' do
        it 'raises ArgumentError'
      end
      it 'sets base_query parameters'
    end
  end
  context 'base_headers' do
    context 'unset' do
      it 'does not send extra headers'
    end
    context 'set' do
      it 'sets base_headers'
    end
  end
  context '#username and #password' do
    context 'unset' do
      it 'does not use basic auth'
    end
    context 'set' do
      it 'uses basic auth'
    end
  end
  context 'HTTP Methods' do
    let(:path) { '/test_path' }
    let(:query) { {query_parameter: 'query_value'} }
    let(:headers) { {header_name: 'header_value'} }
    let(:request_parameters) do
      {
        query: query,
        headers: headers
      }
    end
    let(:body) { 'request_body' }
    def request_has_body? http_method
      Net::HTTP.const_get(http_method.downcase.capitalize)
        .const_get(:REQUEST_HAS_BODY)
    end
    [:get, :head, :post, :put, :delete, :options, :trace, :patch].each do |http_method|
      it "can perform #{http_method.upcase} requests" do
        request_parameters.merge!(body: body) if request_has_body?(http_method)
        request = stub_request(http_method, "#{address}#{path}")
          .with(request_parameters)
        subject.send(http_method, path, request_parameters)
        expect(request).to have_been_requested
      end
    end
  end
  context '#request' do
    it 'can perform generic requests'
  end
end
