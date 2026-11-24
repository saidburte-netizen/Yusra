-- Additive: audit coverage for the record types reached by the shared row
-- actions widget that were not in the original audit trigger list (0009).
-- No RLS changes are needed: existing write policies / SECURITY DEFINER RPCs
-- already authorise these actions, and audit_logs stays select-only for
-- authenticated users (writes happen in triggers only).
do $$
declare t text;
begin
  foreach t in array array['expected_expenses','stock_batches','stock_movements','sale_returns']
  loop
    if to_regclass(format('public.%I', t)) is not null then
      execute format('drop trigger if exists trg_%s_audit on %I', t, t);
      execute format(
        'create trigger trg_%s_audit after insert or update or delete on %I for each row execute function public.audit_row()',
        t, t);
    end if;
  end loop;
end $$;
