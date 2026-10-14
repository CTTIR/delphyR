-- A round moves only forward through its lifecycle, and what was reviewed
-- stays as it was: study, number, protocol, study information and instrument
-- hash never change. The deadline moves only until the round closes; the
-- closing time is set once, when the round closes. Together with the
-- instrument lock this keeps text, order, scales and rules of an opened round.
CREATE FUNCTION ops.protect_round_update() RETURNS trigger LANGUAGE plpgsql AS $$ BEGIN
 IF (NEW.id,NEW.study_id,NEW.number,NEW.protocol_id,NEW.consent_version_id,NEW.instrument_hash)
    IS DISTINCT FROM (OLD.id,OLD.study_id,OLD.number,OLD.protocol_id,OLD.consent_version_id,OLD.instrument_hash) THEN
  RAISE EXCEPTION 'reviewed round is immutable';
 END IF;
 IF NEW.state<>OLD.state AND (OLD.state,NEW.state) NOT IN (('draft','review'),('review','approved'),('approved','open'),('open','closed'),
    ('closed','frozen'),('frozen','analysed'),('analysed','released'),('analysed','finalized'),('released','finalized'),
    ('draft','cancelled'),('review','cancelled'),('approved','cancelled')) THEN
  RAISE EXCEPTION 'round transition refused';
 END IF;
 IF NEW.deadline IS DISTINCT FROM OLD.deadline AND OLD.state NOT IN ('draft','review','approved','open') THEN
  RAISE EXCEPTION 'round deadline locked';
 END IF;
 IF NEW.closed_at IS DISTINCT FROM OLD.closed_at AND NOT (OLD.state='open' AND NEW.state='closed' AND OLD.closed_at IS NULL) THEN
  RAISE EXCEPTION 'round closing time locked';
 END IF;
 RETURN NEW;
END $$;
CREATE TRIGGER round_update_guard BEFORE UPDATE ON research.rounds FOR EACH ROW EXECUTE FUNCTION ops.protect_round_update();
-- An enrollment keeps its round, member and stakeholder group, and its state
-- only moves forward: a submitted or withdrawn enrollment is never reopened.
CREATE FUNCTION ops.protect_enrollment_update() RETURNS trigger LANGUAGE plpgsql AS $$ BEGIN
 IF (NEW.id,NEW.study_id,NEW.round_id,NEW.panelist_id,NEW.group_code)
    IS DISTINCT FROM (OLD.id,OLD.study_id,OLD.round_id,OLD.panelist_id,OLD.group_code) THEN
  RAISE EXCEPTION 'enrollment assignment is immutable';
 END IF;
 IF NEW.state<>OLD.state AND (OLD.state,NEW.state) NOT IN (('eligible','in_progress'),('eligible','submitted'),('in_progress','submitted'),
    ('eligible','withdrawn'),('in_progress','withdrawn')) THEN
  RAISE EXCEPTION 'enrollment transition refused';
 END IF;
 RETURN NEW;
END $$;
CREATE TRIGGER enrollment_update_guard BEFORE UPDATE ON research.enrollments FOR EACH ROW EXECUTE FUNCTION ops.protect_enrollment_update();
-- A study moves from draft to active to completed; completion is final.
CREATE FUNCTION ops.protect_study_update() RETURNS trigger LANGUAGE plpgsql AS $$ BEGIN
 IF NEW.state<>OLD.state AND (OLD.state,NEW.state) NOT IN (('draft','active'),('active','completed')) THEN
  RAISE EXCEPTION 'study transition refused';
 END IF;
 RETURN NEW;
END $$;
CREATE TRIGGER study_update_guard BEFORE UPDATE ON research.studies FOR EACH ROW EXECUTE FUNCTION ops.protect_study_update();
-- A panel member keeps study and pseudonym, and a withdrawal is final.
CREATE FUNCTION ops.protect_panelist_update() RETURNS trigger LANGUAGE plpgsql AS $$ BEGIN
 IF (NEW.id,NEW.study_id) IS DISTINCT FROM (OLD.id,OLD.study_id) OR (NEW.active AND NOT OLD.active) THEN
  RAISE EXCEPTION 'panel membership change refused';
 END IF;
 RETURN NEW;
END $$;
CREATE TRIGGER panelist_update_guard BEFORE UPDATE ON research.panelists FOR EACH ROW EXECUTE FUNCTION ops.protect_panelist_update();
-- A submission and its entries are written only while the round is open and
-- the enrollment is not yet submitted, and a submission holds one answer per
-- response field.
CREATE FUNCTION ops.protect_submission() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE rst text; st text;
BEGIN
 SELECT state INTO rst FROM research.rounds WHERE study_id=NEW.study_id AND id=NEW.round_id FOR SHARE;
 SELECT state INTO st FROM research.enrollments WHERE study_id=NEW.study_id AND id=NEW.enrollment_id FOR UPDATE;
 IF rst IS DISTINCT FROM 'open' OR st IS NULL OR st NOT IN ('eligible','in_progress') THEN RAISE EXCEPTION 'submission locked'; END IF;
 RETURN NEW;
END $$;
CREATE TRIGGER submission_insert_guard BEFORE INSERT ON research.submissions FOR EACH ROW EXECUTE FUNCTION ops.protect_submission();
CREATE OR REPLACE FUNCTION ops.protect_submission_entry() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE rst text; st text;
BEGIN
 SELECT state INTO rst FROM research.rounds WHERE study_id=NEW.study_id AND id=NEW.round_id FOR SHARE;
 SELECT state INTO st FROM research.enrollments WHERE study_id=NEW.study_id AND id=NEW.enrollment_id FOR UPDATE;
 IF rst IS DISTINCT FROM 'open' OR st IS NULL OR st NOT IN ('eligible','in_progress') THEN RAISE EXCEPTION 'submission locked'; END IF;
 IF EXISTS(SELECT 1 FROM research.response_revisions n JOIN research.response_revisions v ON v.study_id=n.study_id AND v.enrollment_id=n.enrollment_id AND v.round_item_id=n.round_item_id AND v.id<>n.id
    JOIN research.submission_entries se ON se.submission_id=NEW.submission_id AND se.response_revision_id=v.id WHERE n.id=NEW.response_revision_id) THEN
  RAISE EXCEPTION 'submission holds the field already';
 END IF;
 RETURN NEW;
END $$;
-- Checked at commit, when a submission is complete: it is committed only
-- together with the enrollment's change to submitted, and it holds every
-- current answer of the enrollment, with each required field answered. An
-- enrollment becomes submitted only together with its submission.
CREATE FUNCTION ops.check_submission() RETURNS trigger LANGUAGE plpgsql AS $$ BEGIN
 IF NOT EXISTS(SELECT 1 FROM research.enrollments WHERE study_id=NEW.study_id AND id=NEW.enrollment_id AND state='submitted')
    OR EXISTS(SELECT 1 FROM research.response_current c JOIN research.response_revisions v ON v.study_id=c.study_id AND v.enrollment_id=c.enrollment_id AND v.round_item_id=c.round_item_id AND v.revision=c.revision
      WHERE c.study_id=NEW.study_id AND c.enrollment_id=NEW.enrollment_id
      AND NOT EXISTS(SELECT 1 FROM research.submission_entries se WHERE se.submission_id=NEW.id AND se.response_revision_id=v.id))
    OR EXISTS(SELECT 1 FROM research.round_items i WHERE i.study_id=NEW.study_id AND i.round_id=NEW.round_id AND i.required
      AND NOT EXISTS(SELECT 1 FROM research.submission_entries se JOIN research.response_revisions v ON v.id=se.response_revision_id
        WHERE se.submission_id=NEW.id AND v.round_item_id=i.id AND v.status<>'not_answered')) THEN
  RAISE EXCEPTION 'submission incomplete';
 END IF;
 RETURN NULL;
END $$;
CREATE CONSTRAINT TRIGGER submission_complete AFTER INSERT ON research.submissions DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION ops.check_submission();
CREATE FUNCTION ops.check_enrollment_submission() RETURNS trigger LANGUAGE plpgsql AS $$ BEGIN
 IF NOT EXISTS(SELECT 1 FROM research.submissions WHERE study_id=NEW.study_id AND enrollment_id=NEW.id) THEN RAISE EXCEPTION 'submission missing'; END IF;
 RETURN NULL;
END $$;
CREATE CONSTRAINT TRIGGER enrollment_submission_present AFTER UPDATE ON research.enrollments DEFERRABLE INITIALLY DEFERRED FOR EACH ROW
 WHEN (NEW.state='submitted' AND OLD.state<>'submitted') EXECUTE FUNCTION ops.check_enrollment_submission();
-- The consent decision is read on every save, submit and delivery check.
CREATE INDEX consents_member ON identity.consents(study_id,membership_id,consent_version_id,recorded_at);
