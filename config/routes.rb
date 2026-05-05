resources :projects, only: [] do
  resources :redmine_sendmail_dispatches,
            only: [:index, :show],
            as:   :sendmail_dispatches,
            path: 'sendmail'
end
