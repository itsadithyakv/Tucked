import { useCallback, useState } from 'react';
import { ScrollView, View } from 'react-native';
import { router, useFocusEffect } from 'expo-router';
import { enCA, isoWeekdayOf, localDateISO, localWeekStartISO } from '@tucked/domain';
import { space } from '@tucked/ui-tokens';
import { useAuth } from '@/lib/auth';
import { useFamily } from '@/lib/childTheme';
import { supabase } from '@/lib/supabase';
import { Avatar } from '@/ui/SwipeChildCard';
import { Body, Button, Caption, Card, Heading, Pill, Screen, Title } from '@/ui/components';

interface MenuRow {
  meal: string;
  description: string;
}

interface SubRow {
  meal: string;
  served: string;
  reason: string;
}

interface BalanceRow {
  household_id: string;
  name: string;
  balance: number;
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

/** Everything that isn't the day itself: the enrolment records, account
 * details — and sign out, deliberately tucked away back here.
 *
 * "Home unwell" used to live here too. It moved to Home: the one question a
 * parent of a sick child has is when they can come back, and it was the
 * fourth card down a tab called More. */
export default function More() {
  const { profile, setViewMode } = useAuth();
  const { children, selected } = useFamily();
  const [recordDone, setRecordDone] = useState<Map<string, number>>(new Map());
  const [menu, setMenu] = useState<MenuRow[]>([]);
  const [todaySubs, setTodaySubs] = useState<SubRow[]>([]);
  const [handbook, setHandbook] = useState<{ version: number; read: boolean } | null>(null);
  const [waitlist, setWaitlist] = useState<WaitlistRow[]>([]);
  const [balances, setBalances] = useState<BalanceRow[]>([]);
  const [receipts, setReceipts] = useState<ReceiptRow[]>([]);

  const tz = selected?.timeZone ?? null;
  const childKey = children.map((c) => c.id).join(',');

  useFocusEffect(
    useCallback(() => {
      if (!profile) return;

      // s. 42: the posted menu, for the CENTRE's today. Only the date-shaped
      // queries wait for a timezone — a family that is only on the waiting
      // list has no enrolled child, and so no centre day, and must still see
      // its place in line.
      if (tz) {
        const today = localDateISO(tz);
        supabase
          .from('menu_item')
          .select('meal, description, week:menu_week_id!inner(week_start)')
          .eq('week.week_start', localWeekStartISO(tz))
          .eq('day_of_week', isoWeekdayOf(today))
          .then(({ data }) => setMenu((data as never as MenuRow[]) ?? []));
        supabase
          .from('menu_substitution')
          .select('meal, served, reason')
          .eq('served_on', today)
          .then(({ data }) => setTodaySubs((data as SubRow[]) ?? []));
      }

      // Fees: what is owed, and the CRA receipts — for the households THIS
      // person belongs to. Two bugs lived here. The balance was read with
      // .maybeSingle(), which errors on more than one row, so a parent in two
      // households (separated parents are a first-class case) silently saw no
      // fees card at all. And nothing scoped it, so a parent who also works at
      // the centre was asked for every household's balance.
      void (async () => {
        const { data: memberships } = await supabase
          .from('household_member')
          .select('household_id')
          .eq('person_id', profile.personId)
          .is('revoked_at', null);
        const householdIds = (memberships ?? []).map((m) => m.household_id as string);
        if (householdIds.length === 0) {
          setBalances([]);
          setReceipts([]);
          return;
        }
        const [{ data: bal }, { data: rec }] = await Promise.all([
          supabase
            .from('household_balance')
            .select('household_id, name, balance')
            .in('household_id', householdIds),
          supabase
            .from('cra_receipt')
            .select('id, tax_year, receipt_number, total_amount, provider_name, provider_business_number, payer_name')
            .in('household_id', householdIds)
            .is('replaced_at', null)
            .order('tax_year', { ascending: false }),
        ]);
        setBalances((bal as BalanceRow[]) ?? []);
        setReceipts((rec as ReceiptRow[]) ?? []);
      })();

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
            .eq('person_id', profile.personId)
            .maybeSingle()
            .then(({ data: ack }) => setHandbook({ version: v.version, read: ack !== null }));
        });

      // s. 72(1): this family's children's records — not every record the
      // viewer's staff role could read
      if (childKey !== '') {
        supabase
          .from('child_record_item')
          .select('child_id, status')
          .in('child_id', childKey.split(','))
          .then(({ data }) => {
            const map = new Map<string, number>();
            for (const i of (data as { child_id: string; status: string }[]) ?? []) {
              if (i.status !== 'missing') map.set(i.child_id, (map.get(i.child_id) ?? 0) + 1);
            }
            setRecordDone(map);
          });
      }
    }, [profile, tz, childKey]),
  );

  const owing = balances.reduce((n, b) => n + Number(b.balance), 0);

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

        {balances.length > 0 && (owing !== 0 || receipts.length > 0) ? (
          <Card>
            <View style={{ flexDirection: 'row', justifyContent: 'space-between', alignItems: 'center', gap: space.sm }}>
              <Heading>Fees</Heading>
              {owing > 0 ? <Pill kind="due">{`$${owing.toFixed(2)} owing`}</Pill> : <Pill kind="ok">Up to date</Pill>}
            </View>
            {balances.length > 1
              ? balances.map((b) => (
                  <Caption key={b.household_id}>{`${b.name}: $${Number(b.balance).toFixed(2)}`}</Caption>
                ))
              : null}
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
                ? `A place is being held for ${w.child_name.split(' ')[0]}${w.respond_by ? ` — please let the centre know by ${new Date(`${w.respond_by}T12:00:00Z`).toLocaleDateString('en-CA', { day: 'numeric', month: 'long', timeZone: 'UTC' })}` : ''}.`
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

        {children.length > 0 ? <Heading>Enrolment records</Heading> : null}
        {children.map((c) => {
          const done = recordDone.get(c.id) ?? 0;
          return (
            <Card key={c.id}>
              <View style={{ flexDirection: 'row', justifyContent: 'space-between', alignItems: 'center', gap: space.sm }}>
                <Body>{c.fullName}</Body>
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

        <Button label="Accident reports" kind="quiet" onPress={() => router.push('/reports')} />

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
