-- Append-only qualitative provenance; originals and reviewed text are distinct.
ALTER TABLE research.response_revisions ADD CONSTRAINT revision_study_id UNIQUE(study_id,id);
CREATE TABLE research.qualitative_sources(
 id uuid PRIMARY KEY, study_id uuid NOT NULL REFERENCES research.studies,
 original_text text NOT NULL CHECK(length(btrim(original_text))>0),
 source_ref text NOT NULL CHECK(length(btrim(source_ref))>0), response_revision_id uuid,
 created_by uuid NOT NULL REFERENCES identity.principals, created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 hash text NOT NULL, UNIQUE(study_id,id),
 FOREIGN KEY(study_id,response_revision_id) REFERENCES research.response_revisions(study_id,id));
CREATE TABLE research.qualitative_edits(
 id uuid PRIMARY KEY, study_id uuid NOT NULL, source_id uuid NOT NULL,
 redacted_text text NOT NULL CHECK(length(btrim(redacted_text))>0),
 reason text NOT NULL CHECK(length(btrim(reason))>0), edited_by uuid NOT NULL REFERENCES identity.principals,
 created_at timestamptz NOT NULL DEFAULT clock_timestamp(), hash text NOT NULL, UNIQUE(study_id,id),
 FOREIGN KEY(study_id,source_id) REFERENCES research.qualitative_sources(study_id,id));
CREATE TABLE research.qualitative_releases(
 id uuid PRIMARY KEY, study_id uuid NOT NULL, edit_id uuid NOT NULL,
 reviewer_id uuid NOT NULL REFERENCES identity.principals, reason text NOT NULL CHECK(length(btrim(reason))>0),
 content_hash text NOT NULL, released_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 UNIQUE(study_id,edit_id), UNIQUE(study_id,id),
 FOREIGN KEY(study_id,edit_id) REFERENCES research.qualitative_edits(study_id,id));
CREATE TABLE research.qualitative_themes(
 id uuid PRIMARY KEY, study_id uuid NOT NULL REFERENCES research.studies,
 code text NOT NULL, version integer NOT NULL CHECK(version>0), label text NOT NULL CHECK(length(btrim(label))>0),
 definition text NOT NULL CHECK(length(btrim(definition))>0), created_by uuid NOT NULL REFERENCES identity.principals,
 created_at timestamptz NOT NULL DEFAULT clock_timestamp(), UNIQUE(study_id,code,version), UNIQUE(study_id,id));
CREATE TABLE research.qualitative_codings(
 id uuid PRIMARY KEY, study_id uuid NOT NULL, source_id uuid NOT NULL, theme_id uuid NOT NULL,
 decision text NOT NULL CHECK(decision IN ('include','exclude')),
 reason text NOT NULL CHECK(length(btrim(reason))>0), coder_id uuid NOT NULL REFERENCES identity.principals,
 created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 FOREIGN KEY(study_id,source_id) REFERENCES research.qualitative_sources(study_id,id),
 FOREIGN KEY(study_id,theme_id) REFERENCES research.qualitative_themes(study_id,id));
CREATE TABLE research.item_provenance_versions(
 id uuid PRIMARY KEY, study_id uuid NOT NULL REFERENCES research.studies, item_code text NOT NULL,
 item_version integer NOT NULL CHECK(item_version>0), UNIQUE(study_id,item_code,item_version), UNIQUE(study_id,id));
CREATE TABLE research.qualitative_item_sources(
 id uuid PRIMARY KEY, study_id uuid NOT NULL, item_id uuid NOT NULL, source_id uuid NOT NULL,
 reason text NOT NULL CHECK(length(btrim(reason))>0), actor_id uuid NOT NULL REFERENCES identity.principals,
 created_at timestamptz NOT NULL DEFAULT clock_timestamp(), UNIQUE(study_id,item_id,source_id),
 FOREIGN KEY(study_id,item_id) REFERENCES research.item_provenance_versions(study_id,id),
 FOREIGN KEY(study_id,source_id) REFERENCES research.qualitative_sources(study_id,id));
CREATE TABLE research.item_lineage_events(
 id uuid PRIMARY KEY, study_id uuid NOT NULL REFERENCES research.studies,
 relation text NOT NULL CHECK(relation IN ('split','merge')), reason text NOT NULL CHECK(length(btrim(reason))>0),
 actor_id uuid NOT NULL REFERENCES identity.principals, created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 hash text NOT NULL, UNIQUE(study_id,id));
CREATE TABLE research.item_lineage_edges(
 study_id uuid NOT NULL, event_id uuid NOT NULL, parent_id uuid NOT NULL, child_id uuid NOT NULL,
 PRIMARY KEY(event_id,parent_id,child_id), CHECK(parent_id<>child_id),
 FOREIGN KEY(study_id,event_id) REFERENCES research.item_lineage_events(study_id,id),
 FOREIGN KEY(study_id,parent_id) REFERENCES research.item_provenance_versions(study_id,id),
 FOREIGN KEY(study_id,child_id) REFERENCES research.item_provenance_versions(study_id,id));
CREATE FUNCTION ops.check_qualitative_release() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE editor uuid; actual_hash text;
BEGIN
 SELECT edited_by,hash INTO editor,actual_hash FROM research.qualitative_edits WHERE study_id=NEW.study_id AND id=NEW.edit_id;
 IF editor=NEW.reviewer_id OR actual_hash<>NEW.content_hash THEN RAISE EXCEPTION 'independent exact review required'; END IF;
 RETURN NEW;
END $$;
CREATE TRIGGER qualitative_release_review BEFORE INSERT ON research.qualitative_releases FOR EACH ROW EXECUTE FUNCTION ops.check_qualitative_release();
CREATE TRIGGER immutable_qualitative_source BEFORE UPDATE OR DELETE ON research.qualitative_sources FOR EACH ROW EXECUTE FUNCTION ops.immutable();
CREATE TRIGGER immutable_qualitative_edit BEFORE UPDATE OR DELETE ON research.qualitative_edits FOR EACH ROW EXECUTE FUNCTION ops.immutable();
CREATE TRIGGER immutable_qualitative_release BEFORE UPDATE OR DELETE ON research.qualitative_releases FOR EACH ROW EXECUTE FUNCTION ops.immutable();
CREATE TRIGGER immutable_qualitative_theme BEFORE UPDATE OR DELETE ON research.qualitative_themes FOR EACH ROW EXECUTE FUNCTION ops.immutable();
CREATE TRIGGER immutable_qualitative_coding BEFORE UPDATE OR DELETE ON research.qualitative_codings FOR EACH ROW EXECUTE FUNCTION ops.immutable();
CREATE TRIGGER immutable_provenance_item BEFORE UPDATE OR DELETE ON research.item_provenance_versions FOR EACH ROW EXECUTE FUNCTION ops.immutable();
CREATE TRIGGER immutable_qualitative_item_source BEFORE UPDATE OR DELETE ON research.qualitative_item_sources FOR EACH ROW EXECUTE FUNCTION ops.immutable();
CREATE TRIGGER immutable_lineage_event BEFORE UPDATE OR DELETE ON research.item_lineage_events FOR EACH ROW EXECUTE FUNCTION ops.immutable();
CREATE TRIGGER immutable_lineage_edge BEFORE UPDATE OR DELETE ON research.item_lineage_edges FOR EACH ROW EXECUTE FUNCTION ops.immutable();
CREATE INDEX qualitative_source_study ON research.qualitative_sources(study_id);
CREATE INDEX qualitative_edit_source ON research.qualitative_edits(study_id,source_id);
CREATE INDEX qualitative_coding_source ON research.qualitative_codings(study_id,source_id);
