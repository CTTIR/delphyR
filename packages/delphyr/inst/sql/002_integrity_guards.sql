CREATE FUNCTION ops.protect_submission_entry() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE st text;
BEGIN
 SELECT state INTO st FROM research.enrollments WHERE study_id=NEW.study_id AND id=NEW.enrollment_id FOR UPDATE;
 IF st NOT IN ('eligible','in_progress') THEN RAISE EXCEPTION 'submission locked'; END IF;
 RETURN NEW;
END $$;
CREATE TRIGGER submission_entry_locked BEFORE INSERT ON research.submission_entries FOR EACH ROW EXECUTE FUNCTION ops.protect_submission_entry();
CREATE FUNCTION ops.protect_response_write() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE rst text; est text;
BEGIN
 SELECT state INTO rst FROM research.rounds WHERE study_id=NEW.study_id AND id=NEW.round_id FOR SHARE;
 SELECT state INTO est FROM research.enrollments WHERE study_id=NEW.study_id AND id=NEW.enrollment_id FOR UPDATE;
 IF rst<>'open' OR est NOT IN ('eligible','in_progress') THEN RAISE EXCEPTION 'response locked'; END IF;
 IF TG_OP='UPDATE' AND (NEW.study_id<>OLD.study_id OR NEW.round_id<>OLD.round_id OR NEW.enrollment_id<>OLD.enrollment_id OR NEW.round_item_id<>OLD.round_item_id) THEN RAISE EXCEPTION 'response move forbidden'; END IF;
 RETURN NEW;
END $$;
CREATE TRIGGER response_revision_locked BEFORE INSERT ON research.response_revisions FOR EACH ROW EXECUTE FUNCTION ops.protect_response_write();
CREATE TRIGGER response_current_locked BEFORE INSERT OR UPDATE ON research.response_current FOR EACH ROW EXECUTE FUNCTION ops.protect_response_write();
CREATE TRIGGER response_current_no_delete BEFORE DELETE ON research.response_current FOR EACH ROW EXECUTE FUNCTION ops.immutable();
CREATE TRIGGER decisions_immutable BEFORE UPDATE OR DELETE ON research.decisions FOR EACH ROW EXECUTE FUNCTION ops.immutable();
CREATE TRIGGER feedback_assignment_locked BEFORE INSERT OR UPDATE OR DELETE ON research.feedback_assignments FOR EACH ROW EXECUTE FUNCTION ops.protect_instrument();
DROP TRIGGER feedback_assignment_locked ON research.feedback_assignments;
CREATE FUNCTION ops.protect_assignment() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE st text;
BEGIN
 IF TG_OP<>'INSERT' THEN RAISE EXCEPTION 'feedback assignment immutable'; END IF;
 SELECT state INTO st FROM research.rounds WHERE study_id=NEW.study_id AND id=NEW.round_id FOR SHARE;
 IF st NOT IN ('draft','review','approved') THEN RAISE EXCEPTION 'feedback assignment locked'; END IF;
 RETURN NEW;
END $$;
CREATE TRIGGER feedback_assignment_locked BEFORE INSERT OR UPDATE OR DELETE ON research.feedback_assignments FOR EACH ROW EXECUTE FUNCTION ops.protect_assignment();
