# frozen_string_literal: true

module Clacky
  class Agent
    module Feedback
      # Extensions prepare a single immutable snapshot before the UI or its
      # countdown sees it. The same snapshot becomes the model's tool result.
      private def prepare_feedback_request(call, result, assistant_message:)
        business_request = result[:feedback_request]
        if result[:error] || result[:success] == false
          raise ArgumentError, "failed tools cannot request feedback"
        end
        args = business_request || (call[:arguments].is_a?(String) ? JSON.parse(call[:arguments]) : call[:arguments])
        request = {
          request_id: call[:id].to_s,
          questions: Tools::AskUser.normalize_questions(args),
          context: Tools::AskUser.fetch_key(args, :context).to_s
        }
        @hooks.trigger(:prepare_feedback, request)
        check_stale!
        request[:request_id] = call[:id].to_s
        request[:questions] = Tools::AskUser.normalize_questions(request)
        raise ArgumentError, "Feedback preparation removed all questions" if request[:questions].empty?

        request[:context] = request[:context].to_s
        request[:answer_context] = request[:answer_context].to_s
        @history.attach_feedback_request(message: assistant_message, tool_call_id: call[:id], request: request)
        summary = business_request && result[:message]
        summary = Tools::AskUser.render_text(request[:questions], request[:context]) if summary.to_s.empty?
        result[:message] = [summary,
                            request[:answer_context]].reject(&:empty?).join("\n\n")
        visible_request = request.reject { |key, _| key == :answer_context }
        result[:feedback_request] = visible_request if business_request
        result[:awaiting_feedback] = true
        visible_request
      end

      # Keep business receipts and full results in history for UI replay. Only
      # the model-facing copy needs the completed summary and Auto instruction.
      private def feedback_messages_for_llm(messages)
        messages.map do |message|
          next message unless message[:role] == "tool" && message[:content].is_a?(String)

          result = JSON.parse(message[:content], symbolize_names: true)
          next message unless result.is_a?(Hash) && result[:feedback_request].is_a?(Hash) && result[:auto_reply]

          message.merge(content: JSON.generate(
            status: result[:status] || "complete",
            message: result[:message].to_s,
            auto_reply: result[:auto_reply]
          ))
        rescue JSON::ParserError
          message
        end
      end
    end
  end
end
