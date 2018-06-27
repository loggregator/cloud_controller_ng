require 'spec_helper'
require 'cloud_controller/diego/reporters/instances_stats_reporter'

module CloudController
  module Diego
    RSpec.describe InstancesStatsReporter do
      subject(:instances_reporter) { InstancesStatsReporter.new(bbs_instances_client, traffic_controller_client) }

      let(:process) { ProcessModelFactory.make(instances: desired_instances) }
      let(:desired_instances) { 1 }
      let(:bbs_instances_client) { instance_double(BbsInstancesClient) }
      let(:traffic_controller_client) { instance_double(TrafficController::Client) }

      let(:two_days_ago_since_epoch_ns) { 2.days.ago.to_f * 1e9 }
      let(:two_days_in_seconds) { 60 * 60 * 24 * 2 }

      def make_actual_lrp(instance_guid:, index:, state:, error:, since:)
        ::Diego::Bbs::Models::ActualLRP.new(
          actual_lrp_key:          ::Diego::Bbs::Models::ActualLRPKey.new(index: index),
          actual_lrp_instance_key: ::Diego::Bbs::Models::ActualLRPInstanceKey.new(instance_guid: instance_guid),
          state:                   state,
          placement_error:         error,
          since:                   since,
        )
      end

      before { Timecop.freeze(Time.at(1.day.ago.to_i)) }
      after { Timecop.return }

      describe '#stats_for_app' do
        let(:desired_instances) { bbs_actual_lrps_response.length }
        let(:bbs_actual_lrps_response) { [actual_lrp_1] }
        let(:bbs_desired_lrp_response) { ::Diego::Bbs::Models::DesiredLRP.new PlacementTags: ['isolation-segment-name'] }
        let(:formatted_current_time) { Time.now.to_datetime.rfc3339 }

        let(:lrp_1_net_info) do
          ::Diego::Bbs::Models::ActualLRPNetInfo.new(
            address: 'lrp-host',
            ports:   [
              ::Diego::Bbs::Models::PortMapping.new(container_port: DEFAULT_APP_PORT, host_port: 2222),
              ::Diego::Bbs::Models::PortMapping.new(container_port: 1111),
            ],
          )
        end
        let(:actual_lrp_1) do
          make_actual_lrp(
            instance_guid: 'instance-a', index: 0, state: ::Diego::ActualLRPState::RUNNING, error: 'some-details', since: two_days_ago_since_epoch_ns
          ).tap do |actual_lrp|
            actual_lrp.actual_lrp_net_info = lrp_1_net_info
          end
        end
        let(:traffic_controller_response) do
          [
            ::TrafficController::Models::Envelope.new(
              origin:          'does-anyone-even-know?',
              eventType:       ::TrafficController::Models::Envelope::EventType::ContainerMetric,
              containerMetric: ::TrafficController::Models::ContainerMetric.new(
                instanceIndex: 0,
                cpuPercentage: 3.92,
                memoryBytes:   564,
                diskBytes:     5000,
              ),
            ),
          ]
        end

        let(:expected_stats_response) do
          {
            0 => {
              state:   'RUNNING',
              isolation_segment: 'isolation-segment-name',
              stats:   {
                name:       process.name,
                uris:       process.uris,
                host:       'lrp-host',
                port:       2222,
                net_info:   lrp_1_net_info.to_hash,
                uptime:     two_days_in_seconds,
                mem_quota:  process.memory * 1024 * 1024,
                disk_quota: process.disk_quota * 1024 * 1024,
                fds_quota:  process.file_descriptors,
                usage:      {
                  time: formatted_current_time,
                  cpu:  0.0392,
                  mem:  564,
                  disk: 5000,
                }
              },
              details: 'some-details',
            },
          }
        end

        before do
          allow(bbs_instances_client).to receive(:lrp_instances).and_return(bbs_actual_lrps_response)
          allow(bbs_instances_client).to receive(:desired_lrp_instance).and_return(bbs_desired_lrp_response)
          allow(traffic_controller_client).to receive(:container_metrics).with(auth_token: 'my-token', app_guid: process.guid).and_return(traffic_controller_response)
          allow(CloudController::SecurityContext).to receive(:auth_token).and_return('my-token')
        end

        it 'returns a map of stats & states per index in the correct units' do
          expect(instances_reporter.stats_for_app(process)).to eq(expected_stats_response)
        end

        context 'when there is no isolation segment for the app' do
          let(:bbs_desired_lrp_response) { ::Diego::Bbs::Models::DesiredLRP.new PlacementTags: [] }

          it 'returns nil for the isolation_segment' do
            expect(instances_reporter.stats_for_app(process)[0][:isolation_segment]).to eq(nil)
          end
        end

        context 'when the default port could not be found' do
          let(:lrp_1_net_info) do
            ::Diego::Bbs::Models::ActualLRPNetInfo.new(
              address: 'lrp-host',
              ports:   [
                ::Diego::Bbs::Models::PortMapping.new(container_port: 1111),
                ::Diego::Bbs::Models::PortMapping.new(container_port: 2222),
              ],
            )
          end

          it 'sets "port" to 0' do
            result = instances_reporter.stats_for_app(process)

            expect(result[0][:stats][:port]).to eq(0)
          end
        end

        context 'when traffic controller somehow returns a partial response without cpuPercentage' do
          # We aren't exactly sure how this happens, but it can happen on an overloaded deployment, see #156707836
          let(:traffic_controller_response) do
            [
              ::TrafficController::Models::Envelope.new(
                origin:          'does-anyone-even-know?',
                eventType:       ::TrafficController::Models::Envelope::EventType::ContainerMetric,
                containerMetric: ::TrafficController::Models::ContainerMetric.new(
                  instanceIndex: 0,
                  memoryBytes:   564,
                ),
              ),
            ]
          end

          it 'sets all the stats to zero' do
            expect(instances_reporter.stats_for_app(process)[0][:stats][:usage]).to eq({
              time: formatted_current_time,
              cpu:  0,
              mem:  0,
              disk: 0,
            })
          end
        end

        context 'when a NoRunningInstances error is thrown' do
          let(:error) { CloudController::Errors::NoRunningInstances.new('ruh roh') }
          let(:expected_stats_response) do
            {
              0 => {
                state:  'DOWN',
                uptime: 0,
              },
            }
          end

          before do
            allow(bbs_instances_client).to receive(:lrp_instances).with(process).and_raise(error)
          end

          it 'shows all instances as "DOWN"' do
            expect(instances_reporter.stats_for_app(process)).to eq(expected_stats_response)
          end
        end

        context 'client data mismatch' do
          context 'when number of actual lrps < desired number of instances' do
            let(:bbs_actual_lrps_response) { [] }
            let(:desired_instances) { 1 }
            let(:expected_stats_response) do
              {
                0 => {
                  state:  'DOWN',
                  uptime: 0,
                },
              }
            end

            it 'provides defaults for unreported instances' do
              expect(instances_reporter.stats_for_app(process)).to eq(expected_stats_response)
            end
          end

          context 'when number of actual lrps > desired number of instances' do
            let(:desired_instances) { 0 }
            let(:traffic_controller_response) { [] }

            it 'ignores superfluous instances' do
              expect(instances_reporter.stats_for_app(process)).to eq({})
            end
          end

          context 'when number of container metrics < desired number of instances' do
            let(:traffic_controller_response) { [] }

            it 'provides defaults for unreported instances' do
              result = instances_reporter.stats_for_app(process)

              expect(result[0][:stats][:usage]).to eq({
                time: formatted_current_time,
                cpu: 0,
                mem: 0,
                disk: 0,
              })
            end
          end

          context 'when an error is raised communicating with diego' do
            let(:error) { StandardError.new('tomato') }
            before do
              allow(bbs_instances_client).to receive(:lrp_instances).with(process).and_raise(error)
            end

            it 'raises an InstancesUnavailable exception' do
              expect { instances_reporter.stats_for_app(process) }.to raise_error(CloudController::Errors::InstancesUnavailable, /tomato/)
            end

            context 'when the error is InstancesUnavailable' do
              let(:error) { CloudController::Errors::InstancesUnavailable.new('ruh roh') }
              let(:mock_logger) { double(:logger, error: nil, debug: nil) }
              before { allow(instances_reporter).to receive(:logger).and_return(mock_logger) }

              it 'reraises the exception and logs the error' do
                expect { instances_reporter.stats_for_app(process) }.to raise_error(CloudController::Errors::InstancesUnavailable, /ruh roh/)
                expect(mock_logger).to have_received(:error).with('stats_for_app.error', { error: 'ruh roh' }).once
              end
            end
          end

          context 'when an error is raised communicating with traffic controller' do
            let(:error) { StandardError.new('tomato') }
            let(:mock_logger) { double(:logger, error: nil, debug: nil) }
            before do
              allow(traffic_controller_client).to receive(:container_metrics).with(auth_token: 'my-token', app_guid: process.guid).and_raise(error)
              allow(instances_reporter).to receive(:logger).and_return(mock_logger)
            end

            it 'raises an InstancesUnavailable exception and logs the error' do
              expect { instances_reporter.stats_for_app(process) }.to raise_error(CloudController::Errors::InstancesUnavailable, /tomato/)
              expect(mock_logger).to have_received(:error).with('stats_for_app.error', { error: 'tomato' }).once
            end

            context 'when the error is InstancesUnavailable' do
              let(:error) { CloudController::Errors::InstancesUnavailable.new('ruh roh') }

              it 'reraises the exception' do
                expect { instances_reporter.stats_for_app(process) }.to raise_error(CloudController::Errors::InstancesUnavailable, /ruh roh/)
              end
            end
          end
        end
      end
    end
  end
end
