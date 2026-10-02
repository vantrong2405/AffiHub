Rails.application.routes.draw do
  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  # Render dynamic PWA files from app/views/pwa/* (remember to link manifest in application.html.erb)
  # get "manifest" => "rails/pwa#manifest", as: :pwa_manifest
  # get "service-worker" => "rails/pwa#service_worker", as: :pwa_service_worker

  get "login", to: "sessions#new", as: :login
  post "login", to: "sessions#create"
  delete "logout", to: "sessions#destroy", as: :logout

  resource :ai_connection, only: [ :show ] do
    collection do
      post :connect
      get :callback_result
    end
    post :test_connection
  end

  resource :affiliate_connection, only: [ :new, :create ]

  resources :products, only: [ :index, :show ] do
    collection do
      post :import
    end
  end

  resources :contents, only: [ :new, :create, :index, :show, :update ] do
    member do
      post :regenerate
      post :approve
      post :reject
    end
  end

  get "social_connections", to: "social_connections#index", as: :social_connections
  get "social_connections/connect", to: "social_connections#connect", as: :connect_social_connections
  get "social_connections/callback", to: "social_connections#callback", as: :social_connections_callback
  get "facebook_pages", to: "facebook_pages#index", as: :facebook_pages
  post "facebook_pages/sync", to: "facebook_pages#sync", as: :sync_facebook_page

  resources :publications, only: [ :new, :create, :show ] do
    member do
      post :post_now
      post :schedule
      post :retry
    end
  end

  root "dashboard#show"
end
