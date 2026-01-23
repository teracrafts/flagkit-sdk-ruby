# frozen_string_literal: true

module FlagKit
  module Types
    # Reasons for flag evaluation results.
    module EvaluationReason
      CACHED = "CACHED"
      DEFAULT = "DEFAULT"
      FLAG_NOT_FOUND = "FLAG_NOT_FOUND"
      BOOTSTRAP = "BOOTSTRAP"
      SERVER = "SERVER"
      STALE_CACHE = "STALE_CACHE"
      ERROR = "ERROR"
      DISABLED = "DISABLED"
      TYPE_MISMATCH = "TYPE_MISMATCH"
      OFFLINE = "OFFLINE"
    end
  end

  # Alias for backward compatibility
  EvaluationReason = Types::EvaluationReason
end
