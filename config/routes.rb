Rails.application.routes.draw do

  use_doorkeeper

  mount RailsAdmin::Engine => '/dashboard', as: 'rails_admin'
  mount APINAME::Root => '/apiname'

  resources :parkings

  devise_for :users
  root to: "home#landing"

  get 'home/landing'
  get 'home/welcome'

  # For details on the DSL available within this file, see http://guides.rubyonrails.org/routing.html
end
