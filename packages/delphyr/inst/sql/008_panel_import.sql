-- Synthetic contact staging is isolated from research responses and account identity.
CREATE TABLE identity.panel_import_receipts(
 id uuid PRIMARY KEY, study_id uuid NOT NULL REFERENCES research.studies,
 file_hash text NOT NULL, preview_hash text NOT NULL, schema_version text NOT NULL CHECK(schema_version='1.0'),
 accepted_rows integer NOT NULL CHECK(accepted_rows>0), rejected_rows integer NOT NULL CHECK(rejected_rows=0),
 actor_id uuid NOT NULL REFERENCES identity.principals, reason text NOT NULL CHECK(length(btrim(reason))>0),
 validation_report jsonb NOT NULL, imported_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 UNIQUE(study_id,id));
CREATE TABLE identity.panel_contacts(
 id uuid PRIMARY KEY, study_id uuid NOT NULL REFERENCES research.studies,
 external_ref text NOT NULL CHECK(length(btrim(external_ref))>0),
 email text NOT NULL CHECK(email LIKE '%.invalid'), display_name text NOT NULL CHECK(length(btrim(display_name))>0),
 locale text NOT NULL CHECK(locale IN ('de','en')), stakeholder_group text NOT NULL,
 import_id uuid NOT NULL, source_row integer NOT NULL CHECK(source_row>0),
 UNIQUE(study_id,id), UNIQUE(study_id,external_ref), UNIQUE(study_id,email),
 FOREIGN KEY(study_id,import_id) REFERENCES identity.panel_import_receipts(study_id,id));
CREATE TABLE identity.panel_invitation_drafts(
 id uuid PRIMARY KEY, study_id uuid NOT NULL, contact_id uuid NOT NULL,
 import_id uuid NOT NULL, state text NOT NULL DEFAULT 'unbound' CHECK(state='unbound'),
 created_at timestamptz NOT NULL DEFAULT clock_timestamp(), UNIQUE(study_id,id), UNIQUE(study_id,contact_id),
 FOREIGN KEY(study_id,contact_id) REFERENCES identity.panel_contacts(study_id,id),
 FOREIGN KEY(study_id,import_id) REFERENCES identity.panel_import_receipts(study_id,id));
CREATE TRIGGER immutable_panel_import BEFORE UPDATE OR DELETE ON identity.panel_import_receipts FOR EACH ROW EXECUTE FUNCTION ops.immutable();
CREATE TRIGGER immutable_panel_contact BEFORE UPDATE OR DELETE ON identity.panel_contacts FOR EACH ROW EXECUTE FUNCTION ops.immutable();
CREATE TRIGGER immutable_panel_invitation_draft BEFORE UPDATE OR DELETE ON identity.panel_invitation_drafts FOR EACH ROW EXECUTE FUNCTION ops.immutable();
