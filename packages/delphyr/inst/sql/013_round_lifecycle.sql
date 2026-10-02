-- A round candidate that was never opened can be withdrawn; its approvals and
-- instrument remain as history. Numbers are unique among active rounds only.
ALTER TABLE research.rounds DROP CONSTRAINT rounds_state_check;
ALTER TABLE research.rounds ADD CONSTRAINT rounds_state_check CHECK(state IN ('draft','review','approved','open','closed','frozen','analysed','feedback_ready','released','finalized','cancelled'));
ALTER TABLE research.rounds DROP CONSTRAINT rounds_study_id_number_key;
CREATE UNIQUE INDEX rounds_active_number ON research.rounds(study_id,number) WHERE state<>'cancelled';
CREATE FUNCTION ops.protect_round_cancellation() RETURNS trigger LANGUAGE plpgsql AS $$ BEGIN
 IF OLD.state='cancelled' AND NEW.state<>'cancelled' THEN RAISE EXCEPTION 'cancelled round is final'; END IF;
 IF NEW.state='cancelled' AND OLD.state NOT IN ('draft','review','approved','cancelled') THEN RAISE EXCEPTION 'opened round cannot be cancelled'; END IF;
 RETURN NEW; END $$;
CREATE TRIGGER round_cancellation_guard BEFORE UPDATE ON research.rounds FOR EACH ROW EXECUTE FUNCTION ops.protect_round_cancellation();
-- Panel members can be enrolled until a round closes. Closed and frozen rounds
-- keep their assigned denominators.
CREATE FUNCTION ops.protect_enrollment_insert() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE st text; BEGIN
 SELECT state INTO st FROM research.rounds WHERE study_id=NEW.study_id AND id=NEW.round_id FOR SHARE;
 IF st IS NULL OR st NOT IN ('draft','review','approved','open') THEN RAISE EXCEPTION 'enrollment closed'; END IF;
 RETURN NEW; END $$;
CREATE TRIGGER enrollment_insert_guard BEFORE INSERT ON research.enrollments FOR EACH ROW EXECUTE FUNCTION ops.protect_enrollment_insert();
