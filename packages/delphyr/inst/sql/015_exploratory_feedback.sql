-- A free-text answer becomes at most one preserved qualitative source.
CREATE UNIQUE INDEX qualitative_source_revision ON research.qualitative_sources(study_id,response_revision_id) WHERE response_revision_id IS NOT NULL;
-- Released feedback is never edited. A correction is a second released
-- feedback of the same analysis that replaces the first for later views;
-- earlier display events keep referring to the version that was shown.
CREATE TABLE research.feedback_corrections(
 id uuid PRIMARY KEY, study_id uuid NOT NULL, feedback_id uuid NOT NULL, replacement_id uuid NOT NULL,
 reason text NOT NULL CHECK(length(btrim(reason))>0),
 impact_note text NOT NULL CHECK(length(btrim(impact_note))>0),
 participant_note text NOT NULL CHECK(length(btrim(participant_note))>0),
 actor_id uuid NOT NULL REFERENCES identity.principals, recorded_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 UNIQUE(study_id,feedback_id), UNIQUE(study_id,replacement_id), CHECK(feedback_id<>replacement_id),
 FOREIGN KEY(study_id,feedback_id) REFERENCES research.feedback(study_id,id),
 FOREIGN KEY(study_id,replacement_id) REFERENCES research.feedback(study_id,id));
CREATE FUNCTION ops.guard_feedback_correction() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE old_analysis uuid; new_analysis uuid; old_state text; new_state text; BEGIN
 SELECT analysis_id,state INTO old_analysis,old_state FROM research.feedback WHERE study_id=NEW.study_id AND id=NEW.feedback_id FOR SHARE;
 SELECT analysis_id,state INTO new_analysis,new_state FROM research.feedback WHERE study_id=NEW.study_id AND id=NEW.replacement_id FOR SHARE;
 IF old_analysis IS DISTINCT FROM new_analysis OR old_state<>'released' OR new_state<>'released'
  OR EXISTS(SELECT 1 FROM research.feedback_corrections WHERE study_id=NEW.study_id AND feedback_id=NEW.replacement_id)
 THEN RAISE EXCEPTION 'feedback correction invalid'; END IF;
 RETURN NEW; END $$;
CREATE TRIGGER validate_feedback_correction BEFORE INSERT ON research.feedback_corrections FOR EACH ROW EXECUTE FUNCTION ops.guard_feedback_correction();
CREATE TRIGGER immutable_feedback_correction BEFORE UPDATE OR DELETE ON research.feedback_corrections FOR EACH ROW EXECUTE FUNCTION ops.immutable();
