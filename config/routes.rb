Rails.application.routes.draw do
  # Health check
  get 'up' => 'rails/health#show', as: :rails_health_check

  # Authentication
  resource :session, only: [ :new, :create, :destroy ]
  get 'login' => 'sessions#new', as: :login
  get 'logout' => 'sessions#destroy', as: :logout

  # Admin namespace
  namespace :admin do
    root to: 'dashboards#show'

    resources :sops do
      collection do
        get :ai_builder
        post :ai_builder_chat
        post :ai_builder_create
      end
      member do
        post :run
      end
      resources :steps, shallow: true
    end

    resources :tasks, only: [ :index, :show ] do
      member do
        post :retry
        post :cancel
      end
    end

    resources :agents, only: [ :index, :show, :edit, :update ] do
      member do
        post :pause
        post :resume
      end
      resources :agent_memories, only: [ :index, :destroy ], shallow: true
    end

    resources :watchers do
      member do
        post :pause
        post :resume
        post :run_now
      end
    end

    resources :credentials, only: [ :index, :show ] do
      member do
        post :refresh
      end
    end

    resources :users, only: [ :index, :new, :create, :edit, :update ]
  end

  # API namespace for webhooks
  namespace :api do
    namespace :v1 do
      post 'webhooks/slack', to: 'webhooks#slack'
      post 'webhooks/email', to: 'webhooks#email'
    end
  end

  # Root redirect to admin
  root to: redirect('/admin')
end
