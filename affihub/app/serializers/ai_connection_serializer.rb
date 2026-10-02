# frozen_string_literal: true

# Never exposes raw token fields (access_token/refresh_token/id_token) — see
# docs/reference-analysis/ai-connection.md Security section.
class AIConnectionSerializer < MainSerializer
  attributes :status, :chatgpt_plan_type, :connected_at
end
