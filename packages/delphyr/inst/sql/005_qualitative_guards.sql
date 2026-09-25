-- Forward extension of the already applied qualitative provenance schema.
ALTER TABLE research.qualitative_edits ADD COLUMN kind text NOT NULL DEFAULT 'redaction' CHECK(kind IN ('redaction','summary'));
ALTER TABLE research.item_lineage_events ADD COLUMN parent_count integer;
ALTER TABLE research.item_lineage_events ADD COLUMN child_count integer;
ALTER TABLE research.item_lineage_events DISABLE TRIGGER immutable_lineage_event;
UPDATE research.item_lineage_events e SET parent_count=(SELECT count(DISTINCT parent_id) FROM research.item_lineage_edges WHERE event_id=e.id), child_count=(SELECT count(DISTINCT child_id) FROM research.item_lineage_edges WHERE event_id=e.id);
ALTER TABLE research.item_lineage_events ENABLE TRIGGER immutable_lineage_event;
ALTER TABLE research.item_lineage_events ALTER COLUMN parent_count SET NOT NULL;
ALTER TABLE research.item_lineage_events ALTER COLUMN child_count SET NOT NULL;
ALTER TABLE research.item_lineage_events ADD CONSTRAINT lineage_cardinality CHECK((relation='split' AND parent_count=1 AND child_count>=2) OR (relation='merge' AND parent_count>=2 AND child_count=1));
CREATE FUNCTION ops.check_lineage_complete() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE eid uuid; expected_parents integer; expected_children integer; actual_edges integer; actual_parents integer; actual_children integer;
BEGIN
 IF TG_TABLE_NAME='item_lineage_events' THEN eid:=NEW.id; ELSE eid:=NEW.event_id; END IF;
 SELECT parent_count,child_count INTO expected_parents,expected_children FROM research.item_lineage_events WHERE id=eid;
 SELECT count(*),count(DISTINCT parent_id),count(DISTINCT child_id) INTO actual_edges,actual_parents,actual_children FROM research.item_lineage_edges WHERE event_id=eid;
 IF actual_edges<>expected_parents*expected_children OR actual_parents<>expected_parents OR actual_children<>expected_children THEN RAISE EXCEPTION 'incomplete or modified lineage event'; END IF;
 RETURN NULL;
END $$;
CREATE CONSTRAINT TRIGGER complete_lineage_event AFTER INSERT ON research.item_lineage_events DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION ops.check_lineage_complete();
CREATE CONSTRAINT TRIGGER complete_lineage_edges AFTER INSERT ON research.item_lineage_edges DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION ops.check_lineage_complete();
