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
        fcontext 'port is 443' do
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
end
