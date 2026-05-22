resources :projects, only: [] do
  resources :redmine_sendmail_dispatches,
            only: [:index, :show],
            as:   :sendmail_dispatches,
            path: 'sendmail'
  match 'sendmail_settings',
        to:  'redmine_sendmail_dispatches#update_project_settings',
        as:  :sendmail_project_settings,
        via: [:put, :patch, :post]
end
