-- Extend supported content locales without rewriting approved text or history.
ALTER TABLE identity.consent_versions DROP CONSTRAINT consent_versions_locale_check;
ALTER TABLE identity.consent_versions ADD CONSTRAINT consent_versions_locale_check CHECK(locale IN ('en','fr','de'));
ALTER TABLE ops.campaigns DROP CONSTRAINT campaigns_locale_check;
ALTER TABLE ops.campaigns ADD CONSTRAINT campaigns_locale_check CHECK(locale IN ('en','fr','de'));
ALTER TABLE identity.panel_contacts DROP CONSTRAINT panel_contacts_locale_check;
ALTER TABLE identity.panel_contacts ADD CONSTRAINT panel_contacts_locale_check CHECK(locale IN ('en','fr','de'));
