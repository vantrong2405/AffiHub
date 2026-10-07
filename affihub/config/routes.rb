Rails.application.routes.draw do
  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  root "dashboard#index"

  resources :video_projects, only: %i[index show new create edit update destroy] do
    resources :source_discoveries, only: %i[new create show]
    resources :source_assets, only: %i[index show new create]
    resources :ai_generation_estimates, only: %i[create show]
    resources :ai_generations, only: %i[new create show edit update]
    resources :render_versions, only: %i[index new create show]
    resources :preflight_reports, only: %i[create show]
    resources :publications, only: %i[index show new create edit update]
    resources :schedules, only: %i[index show new create edit update destroy]
    resources :drive_exports, only: %i[index show create]
    resources :sheet_syncs, only: %i[index show create]
  end

  resources :social_connections, only: %i[index show new create destroy] do
    resources :social_destinations, only: %i[index show create update destroy]
  end

  resources :google_connections, only: %i[index show new create edit update destroy]
  resources :auto_reply_rules, only: %i[index show new create edit update destroy]
  resources :auto_reply_logs, only: %i[index show]

  get "/auth/:provider/callback",
      to: "connection_callbacks#show",
      as: :connection_callback

end
