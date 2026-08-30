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
