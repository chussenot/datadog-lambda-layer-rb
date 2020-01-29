# frozen_string_literal: true

#
# Unless explicitly stated otherwise all files in this repository are licensed
# under the Apache License Version 2.0.
#
# This product includes software developed at Datadog (https://www.datadoghq.com/).
# Copyright 2019 Datadog, Inc.
#

require 'datadog/lambda/trace/context'
require 'datadog/lambda/trace/patch_http'

require 'ddtrace'
require 'ddtrace/sync_writer'

module Datadog
  module Trace
    # TraceListener tracks tracing context information
    class Listener
      def initialize
        Datadog::Trace.patch_http

        # Use the IO transport, and the sync writer to guarantee the trace will
        # be written to logs immediately after being closed.
        Datadog.configure do |c|
          transport = Datadog::Transport::IO.default
          c.tracer writer: Datadog::SyncWriter.new(transport: transport)
        end
      end

      def on_start(event:)
        trace_context = Datadog::Trace.extract_trace_context(event)
        Datadog::Trace.trace_context = trace_context
        Datadog::Utils.logger.debug "extracted trace context #{trace_context}"
      rescue StandardError => e
        Datadog::Utils.logger.error "couldn't read tracing context #{e}"
      end

      def on_end; end

      def on_wrap(request_context:, cold_start:, &block)
        options = {
          tags: {
            cold_start: cold_start,
            function_arn: request_context.invoked_function_arn,
            request_id: request_context.aws_request_id,
            resource_names: request_context.function_name
          }
        }
        unless Datadog::Trace.trace_context.nil?
          trace_id = Datadog::Trace.trace_context['trace_id']
          span_id = Datadog::Trace.trace_context['parent_id']
          context = Datadog::Context.new(trace_id: trace_id, span_id: span_id)
          options['child_of'] = context
        end

        Datadog.tracer.trace('aws.lambda', options) do |_span|
          block.call
        end
      end
    end
  end
end
