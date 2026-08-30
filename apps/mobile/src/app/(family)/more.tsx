import { useCallback, useState } from 'react';
import { ScrollView, View } from 'react-native';
import { router, useFocusEffect } from 'expo-router';
import { enCA } from '@tucked/domain';
import { space } from '@tucked/ui-tokens';
import { useAuth } from '@/lib/auth';
import { supabase } from '@/lib/supabase';
import { Avatar } from '@/ui/SwipeChildCard';
import { Body, Button, Caption, Card, Heading, Pill, Screen, Title } from '@/ui/components';

interface ChildRow {
  id: string;
  full_name: string;
}

interface MenuRow {
  day_of_week: number;
  meal: string;
  description: string;
}

interface SubRow {
  meal: string;
  served: string;
  reason: string;
}

interface FeesRow {
  balance: number;
  paid: number;
}

interface ReceiptRow {
  id: string;
  tax_year: number;
  receipt_number: string;
  total_amount: number;
  provider_name: string;
  provider_business_number: string | null;
  payer_name: string;
}

interface ExclusionRow {
  id: string;
  exclusion_reason: string;
  return_criteria: string;
  may_return_at: string | null;
  child: { full_name: string } | null;
}

interface WaitlistRow {
  entry_id: string;
  child_name: string;
  age_group: string;
  status: string;
  list_position: number;
  families_ahead: number;
  list_length: number;
  respond_by: string | null;
}

const MEAL_ORDER = ['breakfast', 'snack_am', 'lunch', 'snack_pm'];
const MEAL_LABELS: Record<string, string> = {
  breakfast: 'Breakfast',
  snack_am: 'Morning snack',
  lunch: 'Lunch',
  snack_pm: 'Afternoon snack',
};

function isoDow(d: Date): number {
  return d.getDay() === 0 ? 7 : d.getDay();
}

/** Everything that isn't the day itself: the enrolment records, account
 * details — and sign out, deliberately tucked away back here. */
export default function More() {
  const { profile, setViewMode } = useAuth();
  const [children, setChildren] = useState<ChildRow[]>([]);
  const [recordDone, setRecordDone] = useState<Map<string, number>>(new Map());
  const [menu, setMenu] = useState<MenuRow[]>([]);
  const [todaySubs, setTodaySubs] = useState<SubRow[]>([]);
  const [handbook, setHandbook] = useState<{ version: number; read: boolean } | null>(null);
  const [waitlist, setWaitlist] = useState<WaitlistRow[]>([]);
  const [exclusions, setExclusions] = useState<ExclusionRow[]>([]);
  const [fees, setFees] = useState<FeesRow | null>(null);
  const [receipts, setReceipts] = useState<ReceiptRow[]>([]);

  useFocusEffect(
    useCallback(() => {
      // s. 42: the posted menu is posted where parents can see it — RLS shows
      // families posted weeks only, so this is simply "today's meals".
      const today = new Date();
      const monday = new Date(Date.UTC(today.getFullYear(), today.getMonth(), today.getDate()));
      monday.setUTCDate(monday.getUTCDate() - (isoDow(today) - 1));
      supabase
        .from('menu_item')
        .select('day_of_week, meal, description, week:menu_week_id!inner(week_start)')
        .eq('week.week_start', monday.toISOString().slice(0, 10))
        .eq('day_of_week', isoDow(today))
        .then(({ data }) => setMenu((data as never as MenuRow[]) ?? []));
      supabase
        .from('menu_substitution')
        .select('meal, served, reason')
        .eq('served_on', today.toISOString().slice(0, 10))
        .then(({ data }) => setTodaySubs((data as SubRow[]) ?? []));
      supabase
        .from('child')
        .select('id, full_name')
        .order('full_name')
        .then(({ data }) => setChildren(data ?? []));
      // Fees: what is owed, and the CRA receipts. Nothing here ever gates the
      // app — a balance changes what this card says and nothing else.
      supabase
        .from('household_balance')
        .select('balance, paid')
        .maybeSingle()
        .then(({ data }) => setFees((data as FeesRow | null) ?? null));
      supabase
        .from('cra_receipt')
        .select('id, tax_year, receipt_number, total_amount, provider_name, provider_business_number, payer_name')
        .is('replaced_at', null)
        .order('tax_year', { ascending: false })
        .then(({ data }) => setReceipts((data as ReceiptRow[]) ?? []));
      // s. 36: a child home unwell, and the plain answer to "when can she
      // come back?" — the centre's own policy, not a guess at the door.
      supabase
        .from('health_exclusion')
        .select('id, exclusion_reason, return_criteria, may_return_at, child:child_id(full_name)')
        .is('returned_at', null)
        .then(({ data }) => setExclusions((data as never) ?? []));
      // s. 75.1: your own place on the waiting list — the count is of the
      // whole list, but no other family's row ever comes back with it.
      supabase
        .rpc('my_waitlist_positions')
        .then(({ data }) => setWaitlist((data as WaitlistRow[]) ?? []));
      // s. 45: the handbook the centre must give you, and whether you have
      // told them you have it.
      supabase
        .from('handbook_version')
        .select('id, version')
        .order('version', { ascending: false })
        .limit(1)
        .maybeSingle()
        .then(({ data }) => {
          const v = data as { id: string; version: number } | null;
          if (!v) {
            setHandbook(null);
            return;
          }
          supabase
            .from('handbook_acknowledgement')
            .select('acknowledged_at')
            .eq('handbook_version_id', v.id)
            .maybeSingle()
            .then(({ data: ack }) => setHandbook({ version: v.version, read: ack !== null }));
        });
      supabase
        .from('child_record_item')
        .select('child_id, status')
        .then(({ data }) => {
          const map = new Map<string, number>();
          for (const i of (data as { child_id: string; status: string }[]) ?? []) {
            if (i.status !== 'missing') map.set(i.child_id, (map.get(i.child_id) ?? 0) + 1);
          }
          setRecordDone(map);
        });
    }, []),
  );

  return (
    <Screen>
      <ScrollView contentContainerStyle={{ gap: space.cardGap, paddingBottom: space.x2l }}>
        <Title>More</Title>
        {profile ? (
          <Card>
            <View style={{ flexDirection: 'row', alignItems: 'center', gap: space.md }}>
              <Avatar name={profile.fullName} size={44} />
              <View>
                <Heading>{profile.fullName}</Heading>
                <Caption>Family account</Caption>
              </View>
            </View>
          </Card>
        ) : null}

        {menu.length > 0 ? (
          <Card wash="mint">
            <Heading>Today&apos;s menu</Heading>
            {MEAL_ORDER.map((meal) => {
              const planned = menu.find((m) => m.meal === meal);
              if (!planned) return null;
              const sub = todaySubs.find((s) => s.meal === meal);
              return (
                <View key={meal} style={{ gap: 2 }}>
                  <Caption>{MEAL_LABELS[meal]}</Caption>
                  {sub ? (
                    <>
                      <Body>{sub.served}</Body>
                      <Caption>{`Instead of ${planned.description} — ${sub.reason}`}</Caption>
                    </>
                  ) : (
                    <Body>{planned.description}</Body>
                  )}
                </View>
              );
            })}
          </Card>
        ) : null}

        {fees && (Number(fees.balance) !== 0 || receipts.length > 0) ? (
          <Card>
            <View style={{ flexDirection: 'row', justifyContent: 'space-between', alignItems: 'center', gap: space.sm }}>
              <Heading>Fees</Heading>
              {Number(fees.balance) > 0 ? (
                <Pill kind="due">{`$${Number(fees.balance).toFixed(2)} owing`}</Pill>
              ) : (
                <Pill kind="ok">Up to date</Pill>
              )}
            </View>
            {receipts.map((r) => (
              <View key={r.id} style={{ gap: 2 }}>
                <Body>{`${r.tax_year} tax receipt — $${Number(r.total_amount).toFixed(2)}`}</Body>
                <Caption>
                  {`Receipt ${r.receipt_number} · ${r.provider_name}${r.provider_business_number ? ` · BN ${r.provider_business_number}` : ''} · issued to ${r.payer_name}`}
                </Caption>
              </View>
            ))}
            <Caption>
              Keep the receipt for your tax return. Your child&apos;s place, records and this app are
              never affected by a balance.
            </Caption>
          </Card>
        ) : null}

        {exclusions.map((e) => (
          <Card key={e.id} wash="sand">
            <View style={{ flexDirection: 'row', justifyContent: 'space-between', alignItems: 'center', gap: space.sm }}>
              <Heading>{`${e.child?.full_name.split(' ')[0] ?? 'Your child'} is home unwell`}</Heading>
              <Pill kind="due">Away</Pill>
            </View>
            <Body>{e.exclusion_reason}</Body>
            <Body muted>{`Before coming back: ${e.return_criteria}`}</Body>
            {e.may_return_at ? (
              <Caption>
                {`Earliest return: ${new Date(e.may_return_at).toLocaleString('en-CA', { weekday: 'long', hour: '2-digit', minute: '2-digit', hour12: false })}. If a doctor says sooner, tell the centre and bring the note.`}
              </Caption>
            ) : null}
          </Card>
        ))}

        {waitlist.map((w) => (
          <Card key={w.entry_id} wash={w.status === 'offered' ? 'sand' : 'mist'}>
            <View style={{ flexDirection: 'row', justifyContent: 'space-between', alignItems: 'center', gap: space.sm }}>
              <Heading>{`${w.child_name.split(' ')[0]} — waiting list`}</Heading>
              <Pill kind={w.status === 'offered' ? 'now' : 'ok'}>
                {w.status === 'offered' ? 'Place offered' : `Number ${w.list_position}`}
              </Pill>
            </View>
            <Body>
              {w.status === 'offered'
                ? `A place is being held for ${w.child_name.split(' ')[0]}${w.respond_by ? ` — please let the centre know by ${new Date(`${w.respond_by}T12:00:00`).toLocaleDateString('en-CA', { day: 'numeric', month: 'long' })}` : ''}.`
                : w.families_ahead === 0
                  ? `Next in line for a ${w.age_group} place.`
                  : `${w.families_ahead} ${w.families_ahead === 1 ? 'family is' : 'families are'} ahead, out of ${w.list_length} waiting for a ${w.age_group} place.`}
            </Body>
            <Caption>
              Places are offered in the order set out in the handbook. There is never a fee to be on the
              list.
            </Caption>
          </Card>
        ))}

        {handbook ? (
          <Card wash={handbook.read ? undefined : 'sand'}>
            <View style={{ flexDirection: 'row', justifyContent: 'space-between', alignItems: 'center', gap: space.sm }}>
              <Heading>Parent handbook</Heading>
              <Pill kind={handbook.read ? 'ok' : 'due'}>{handbook.read ? 'Read' : 'Please read'}</Pill>
            </View>
            <Body muted>
              {handbook.read
                ? `Version ${handbook.version} — fees, hours, safe dismissal and everything else, in one place.`
                : `Version ${handbook.version} is ready. Have a read and let the centre know you have it.`}
            </Body>
            <Button label="Open the handbook" kind="quiet" onPress={() => router.push('/handbook')} />
          </Card>
        ) : null}

        <Heading>Enrolment records</Heading>
        {children.map((c) => {
          const done = recordDone.get(c.id) ?? 0;
          return (
            <Card key={c.id}>
              <View style={{ flexDirection: 'row', justifyContent: 'space-between', alignItems: 'center', gap: space.sm }}>
                <Body>{c.full_name}</Body>
                <Pill kind={done >= 11 ? 'ok' : 'due'}>{done >= 11 ? 'Complete' : `${done} of 11`}</Pill>
              </View>
              <Button
                label={done >= 11 ? 'Review record' : 'Complete record'}
                kind="quiet"
                onPress={() => router.push({ pathname: '/enrolment/[childId]', params: { childId: c.id } })}
              />
            </Card>
          );
        })}

        <Button
          label="Accident reports"
          kind="quiet"
          onPress={() => router.push('/reports')}
        />

        {profile?.dualRole ? (
          <Card wash="mist">
            <Heading>You also work at the centre</Heading>
            <Body muted>Switch to Room view to run the day; your family view stays right here.</Body>
            <Button label="Switch to Room view" kind="quiet" onPress={() => setViewMode('room')} />
          </Card>
        ) : null}

        <Card>
          <Heading>About sign-in</Heading>
          <Body muted>
            Your centre invites you by email. Signing in sends a one-time link to that address —
            open it on this phone and you are in. No password to remember or lose.
          </Body>
        </Card>

        <Button label={enCA.auth.signOut} kind="quiet" onPress={() => supabase.auth.signOut()} />
      </ScrollView>
    </Screen>
  );
}
