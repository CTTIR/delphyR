CREATE FUNCTION ops.guard_invitation_revocation() RETURNS trigger LANGUAGE plpgsql AS $$ BEGIN
 PERFORM 1 FROM identity.panel_invitations WHERE study_id=NEW.study_id AND id=NEW.invitation_id FOR UPDATE;
 IF EXISTS(SELECT 1 FROM identity.panel_invitation_acceptances WHERE invitation_id=NEW.invitation_id) THEN RAISE EXCEPTION 'invitation already accepted'; END IF;
 RETURN NEW; END $$;
CREATE TRIGGER validate_invitation_revocation BEFORE INSERT ON identity.panel_invitation_revocations FOR EACH ROW EXECUTE FUNCTION ops.guard_invitation_revocation();
