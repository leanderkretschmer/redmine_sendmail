resources :projects, only: [] do
  resources :redmine_sendmail_dispatches,
            only: [:index, :show],
            as:   :sendmail_dispatches,
            path: 'sendmail' do
    member do
      post :resend, as: 'resend'
    end
    collection do
      post :preview, as: 'preview'
    end
  end
  match 'sendmail_settings',
        to:  'redmine_sendmail_dispatches#update_project_settings',
        as:  :sendmail_project_settings,
        via: [:put, :patch, :post]
  match 'sendmail_contact_kennungen/:contact_id',
        to:  'redmine_sendmail_contact_kennungen#update',
        as:  :sendmail_contact_kennung,
        via: [:patch, :put, :post]
end
