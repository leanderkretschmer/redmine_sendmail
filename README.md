# Redmine Sendmail

Sendet Ticket-Kommentare als E-Mail an Kontakte aus dem **Redmine CRM (`redmine_contacts`)** Plugin direkt aus dem Ticket-Formular.

## Funktion

1. Im Ticket einen Kommentar schreiben (noch nicht speichern).
2. Unter dem Kommentarfeld einen Empfänger aus den Projekt-Kontakten auswählen.
3. Es erscheint ein Betreff-Feld &mdash; Betreff eintragen.
4. Ticket speichern. Der Kommentar wird automatisch als E-Mail mit Betreff `[#TICKET-ID] BETREFF` und einem in den Plugin-Einstellungen konfigurierten Footer (mit dem Namen des angemeldeten Benutzers) versendet.

## Installation

```bash
cd <REDMINE>/plugins
git clone … redmine_sendmail
cd <REDMINE>
bundle install
bundle exec rake redmine:plugins:migrate NAME=redmine_sendmail RAILS_ENV=production
# Web-/Worker-Prozess neu starten
```

Voraussetzungen:

* Redmine **6.0+**
* Plugin **`redmine_contacts`** (für die Empfänger-Auswahl)
* Eine in `configuration.yml` korrekt konfigurierte ActionMailer-/SMTP-Verbindung &mdash; das Plugin nutzt den Standard-Mailversand von Redmine.

## Einrichtung

1. Unter *Administration → Plugins → Redmine Sendmail* die Vorlagen pflegen:
   * **Betreff-Vorlage** (z. B. `[#{ticket_id}] {custom_subject}`)
   * **Body-Vorlage / Footer** mit Platzhaltern wie `{user_name}`, `{user_email}`, `{comment}`, `{ticket_url}`
   * Optional: feste Absender-Adresse, Reply-To, Versand-Logging
2. Im Projekt unter *Einstellungen → Module* das Modul **„Sendmail“** aktivieren.
3. Mitgliedern die Berechtigung **„E-Mails an Kontakte senden“** geben.

Versendete Mails werden (sofern Logging aktiviert) im Projektmenü **„Mail-Versand“** aufgelistet.

## Platzhalter

`{user_name}`, `{user_login}`, `{user_firstname}`, `{user_lastname}`, `{user_email}`,
`{ticket_id}`, `{ticket_subject}`, `{ticket_url}`,
`{project_name}`, `{project_identifier}`,
`{recipient_name}`, `{recipient_email}`,
`{custom_subject}`, `{comment}`, `{date}`
