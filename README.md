# Redmine Sendmail

Sendet Ticket-Kommentare als E-Mail an Kontakte aus dem **Redmine CRM (`redmine_contacts`)** Plugin direkt aus dem Ticket-Formular.

## Funktion

### Kommentar als E-Mail

1. Im Ticket einen Kommentar schreiben (noch nicht speichern).
2. Unter dem Kommentarfeld einen Empfänger aus den Projekt-Kontakten auswählen.
3. Es erscheint ein Betreff-Feld &mdash; Betreff eintragen.
4. Ticket speichern. Der Kommentar wird automatisch als E-Mail mit Betreff `[#TICKET-ID] BETREFF` und einem in den Plugin-Einstellungen konfigurierten Footer (mit dem Namen des angemeldeten Benutzers) versendet.

### Neues Ticket als E-Mail

1. Beim Anlegen eines Tickets Titel und Beschreibung (gerne mit Bildern) ausfüllen.
2. Unter der Beschreibung einen oder mehrere Empfänger aus den Projekt-Kontakten auswählen.
3. Ticket anlegen. Die Beschreibung wird als E-Mail versendet &mdash; der **Ticket-Titel** ist der Betreff (über die Betreff-Vorlage, also standardmäßig `[#TICKET-ID] TITEL`), die Beschreibung der Mailtext. Inline-Bilder werden als Datei-Anhang mitgeschickt.

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
   * Optional: **Absender-Adresse**, **Absender-Name** und **Reply-To** — alle drei
     unterstützen Platzhalter (z. B. `{projekt-kennung}@example.com`, `Support {project_name}`).
   * Optional: Versand-Logging
2. Im Projekt unter *Einstellungen → Module* das Modul **„Sendmail“** aktivieren.
3. Mitgliedern die Berechtigung **„E-Mails an Kontakte senden“** geben.
4. Optional (nur Redmine-**Admins**): pro Projekt unter *Einstellungen → Mail-Versand*
   können folgende Werte gepflegt werden:
   * **Projekt-Info 1/2** &mdash; freie Werte, in allen Vorlagen als
     `{project_info_1}` / `{project_info_2}` nutzbar.
   * **Betreff-/Body-Vorlage** sowie **Absender-Adresse / Absender-Name / Reply-To**
     als Projekt-Overrides &mdash; gesetzte Felder ersetzen die globalen Vorlagen
     ausschließlich für dieses Projekt; leere Felder erben die globale Einstellung.
   * **Eigenes SMTP-Konto** &mdash; Mails dieses Projekts werden dann über das
     Projekt-SMTP-Konto verschickt (oder optional über das Konto aus
     `redmine_mail_handler`); ohne Override gilt die globale Versand-Konfiguration.

   Der Tab erscheint nur, wenn das Modul *Sendmail* im Projekt aktiviert ist und der
   angemeldete Benutzer ein Redmine-Administrator ist.

Beim Versand wird Redmines Inline-Bild-Syntax (z. B.
`!Bildschirmfoto%202026-05-22%20um%2013.23.43.png!`) aus dem Mailtext entfernt;
die zugehörigen Bilder werden stattdessen als Datei-Anhang mitgeschickt.

Versendete Mails werden (sofern Logging aktiviert) im Projektmenü **„Mail-Versand“** aufgelistet.

## Vorschau, Versendet-Markierung, Suche

* **Empfänger-Suche** &mdash; Über der Kontaktliste im Ticket-/Kommentar-Formular
  steht ein Suchfeld, das die Liste live nach Name und E-Mail filtert.
* **Mail-Vorschau** &mdash; Wird das Ticket oder der Kommentar mit mindestens
  einem Empfänger gespeichert, erscheint vor dem tatsächlichen Speichern ein
  Vorschau-Dialog: Betreff, Absender, Antwort-An und der vollständig
  ausgefüllte Mailtext (Platzhalter ersetzt). Empfängerspezifische
  Platzhalter (z. B. `{recipient_name}`, `{kunden-projekt-kennung}`) werden
  in der Vorschau mit den Werten des **ersten** ausgewählten Kontakts
  angezeigt; pro tatsächlich versendeter Mail werden die Werte des jeweiligen
  Empfängers eingesetzt. Buttons: *Senden* (speichert + versendet),
  *Bearbeiten* (zurück ins Formular).
* **Speichern & Senden** &mdash; Ist mindestens ein Empfänger ausgewählt,
  trägt der Speichern-Button des Tickets/Kommentars die Beschriftung
  „Speichern & Senden“, ansonsten weiterhin „Speichern“.
* **Versendet-Markierung am Ticket** &mdash; Wurde das Ticket beim Anlegen
  als E-Mail versendet, erscheint die Empfänger-Liste auch direkt unter der
  Ticket-Beschreibung (bisher nur unter dem jeweiligen Kommentar).
* **Aufräumen bei Kommentar-Löschung** &mdash; Wird ein Kommentar gelöscht,
  werden die zugehörigen Versand-Einträge mitgelöscht, sodass die
  „Per E-Mail versendet an …“-Markierung verschwindet.

## Platzhalter

`{user_name}`, `{user_login}`, `{user_firstname}`, `{user_lastname}`, `{user_email}`,
`{ticket_id}`, `{ticket_subject}`, `{ticket_url}`,
`{project_name}`, `{project_identifier}`, `{projekt-kennung}`,
`{project_info_1}`, `{project_info_2}`,
`{recipient_name}`, `{recipient_email}`,
`{kunden-projekt-kennung}` (pro Kontakt × Projekt, am Kontakt unter
*Kontakt-Detailseite → Mail-Versand: Kunden-Projekt-Kennung* pflegen — nur Admins),
`{custom_subject}`, `{comment}`, `{date}`

Die Platzhalter funktionieren in Betreff- und Body-Vorlage sowie in den Feldern
Absender-Adresse, Absender-Name und Reply-To.

## Versand-Status, Bounce-Diagnose und erneutes Senden

Der Status (`sent` / `failed`) wird aus dem Ergebnis von ActionMailers
`deliver_now` gesetzt — also dem tatsächlichen Antwortverhalten des
SMTP-Servers. Schlägt der Versand fehl, klassifiziert das Plugin die Ursache
nach den gängigen SMTP-Mustern (z. B. `5.1.1` → *user unknown*) und prüft per
DNS-MX-Lookup, ob die Empfänger-Domain überhaupt einen Mailserver hat. Das
Ergebnis steht in der Spalte `failure_reason_detail` und erscheint im
Mail-Versand-Log (Projektmenü „Mail-Versand“) als Tooltip neben dem
`Fehler`-Status. Mögliche Codes: `invalid_address`, `domain_not_resolvable`,
`domain_no_mx`, `mailbox_unknown`, `mailbox_full`, `auth_failed`,
`rate_limited`, `spam_blocked`, `smtp_error`.

Administratoren sehen in der Detailansicht einer Mail einen **„Erneut
senden“**-Button. Der Resend nutzt den gespeicherten Betreff/Mailtext und die
*aktuelle* Sender-/SMTP-Konfiguration (so kann ein vorher konfigurierter
Fehler korrigiert werden, ohne dass der Original-Kommentar erneut bearbeitet
werden muss). Es wird ein neuer Log-Eintrag erzeugt; der ursprünglich
fehlgeschlagene Eintrag bleibt zur Nachvollziehbarkeit bestehen.

## JSON-API

Die versendeten Mails sind authentifiziert (Redmine-API-Key oder Session)
abrufbar:

| Methode | Pfad                                                        | Zweck                                                                 |
|---------|-------------------------------------------------------------|------------------------------------------------------------------------|
| GET     | `/projects/:project_id/sendmail.json`                       | Alle Versand-Einträge des Projekts                                     |
| GET     | `/projects/:project_id/sendmail.json?journal_id=N`          | Alle Empfänger, die für **Kommentar** N versendet wurden               |
| GET     | `/projects/:project_id/sendmail.json?issue_id=N`            | Alle Empfänger, die für **Ticket** N versendet wurden                  |
| GET     | `/projects/:project_id/sendmail/:id.json`                   | Einzelner Versand                                                       |

Antwortformat (vereinfacht):

```json
{
  "dispatches": [
    {
      "id": 42,
      "created_at": "2026-05-27T11:23:45Z",
      "project_id": 2,
      "issue_id": 17,
      "journal_id": 89,
      "recipient_name": "Max Mustermann",
      "recipient_email": "max@example.com",
      "subject": "[#17] Anfrage Wartung",
      "status": "sent",
      "error_message": null,
      "failure_reason_detail": null
    }
  ],
  "total_count": 1
}
```

Voraussetzungen: API-Zugriff in *Administration → Einstellungen → API* aktiviert,
und der API-User benötigt die Permission **„E-Mails an Kontakte senden“** im
Projekt (entspricht der Sichtbarkeit des Mail-Versand-Logs in der UI).
