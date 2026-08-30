import { useCallback, useState } from 'react';
import { router, useFocusEffect } from 'expo-router';
import { View } from 'react-native';
import { enCA } from '@tucked/domain';
import { space } from '@tucked/ui-tokens';
import { useAuth } from '@/lib/auth';
import { RecorderProvider, useRecorder } from '@/lib/recorder';
import { loadRoomDay } from '@/lib/roomData';
import { runCommand } from '@/lib/queue';
import { supabase } from '@/lib/supabase';
import { Avatar } from '@/ui/SwipeChildCard';
import { Body, Button, Caption, Card, Field, Heading, Pill, Screen, Sheet, Title } from '@/ui/components';

interface DueTask {
  id: string;
  title: string;
  regulation: string;
  next_due_on: string;
}

interface MenuRow {
  meal: string;
  description: string;
}

interface SubRow {
  meal: string;
  served: string;
  reason: string;
}

const MEAL_ORDER = ['breakfast', 'snack_am', 'lunch', 'snack_pm'] as const;
const MEAL_LABELS: Record<string, string> = {
  breakfast: 'Breakfast',
  snack_am: 'Morning snack',
  lunch: 'Lunch',
  snack_pm: 'Afternoon snack',
};

function isoDow(d: Date): number {
  return d.getDay() === 0 ? 7 : d.getDay();
}

/** s. 42: today's posted menu, with the substitution recorded AT THE TIME —
 * on the device that is standing in the kitchen when the delivery fails. */
function TodaysMenu() {
  const { getRecorder } = useRecorder();
  const [menu, setMenu] = useState<MenuRow[]>([]);
  const [subs, setSubs] = useState<SubRow[]>([]);
  const [centreId, setCentreId] = useState<string | null>(null);
  const [open, setOpen] = useState<string | null>(null);
  // kept after `open` clears so the sheet title does not blank mid-animation
  const [openLabel, setOpenLabel] = useState('');
  const [served, setServed] = useState('');
  const [reason, setReason] = useState('');
  const [notice, setNotice] = useState<string | null>(null);

  const refresh = useCallback(() => {
    const today = new Date();
    const monday = new Date(Date.UTC(today.getFullYear(), today.getMonth(), today.getDate()));
    monday.setUTCDate(monday.getUTCDate() - (isoDow(today) - 1));
    supabase
      .from('menu_item')
      .select('meal, description, centre_id, week:menu_week_id!inner(week_start)')
      .eq('week.week_start', monday.toISOString().slice(0, 10))
      .eq('day_of_week', isoDow(today))
      .then(({ data }) => {
        const rows = (data as never as (MenuRow & { centre_id: string })[]) ?? [];
        setMenu(rows);
        setCentreId(rows[0]?.centre_id ?? null);
      });
    supabase
      .from('menu_substitution')
      .select('meal, served, reason')
      .eq('served_on', today.toISOString().slice(0, 10))
      .then(({ data }) => setSubs((data as SubRow[]) ?? []));
  }, []);
  useFocusEffect(refresh);

  async function saveSubstitution() {
    if (!open || !centreId) return;
    if (served.trim().length === 0 || reason.trim().length === 0) {
      setNotice('Record what was served instead, and why.');
      return;
    }
    const meal = open;
    setOpen(null);
    const recorder = await getRecorder();
    if (!recorder) return;
    const result = await runCommand('record_menu_substitution', {
      p_centre: centreId,
      p_served_on: null,
      p_meal: meal,
      p_served: served.trim(),
      p_reason: reason.trim(),
      p_recorder: recorder.personId,
      p_pin: recorder.pin,
    });
    setServed('');
    setReason('');
    setNotice(result.ok ? 'Substitution recorded on today’s menu.' : (result.error ?? 'Could not record — it will retry.'));
    refresh();
  }

  if (menu.length === 0) return null;

  return (
    <Card>
      <Heading>Today&apos;s menu</Heading>
      {MEAL_ORDER.map((meal) => {
        const planned = menu.find((m) => m.meal === meal);
        if (!planned) return null;
        const sub = subs.find((s) => s.meal === meal);
        return (
          <View key={meal} style={{ flexDirection: 'row', alignItems: 'center', gap: space.sm }}>
            <View style={{ flex: 1 }}>
              <Caption>{MEAL_LABELS[meal]}</Caption>
              <Body>{sub ? sub.served : planned.description}</Body>
              {sub ? <Caption>{`Substituted — ${sub.reason}`}</Caption> : null}
            </View>
            {sub ? (
              <Pill kind="due">Substituted</Pill>
            ) : (
              <Button
                label="Changed"
                kind="quiet"
                onPress={() => {
                  setServed('');
                  setReason('');
                  setNotice(null);
                  setOpenLabel(MEAL_LABELS[meal] ?? '');
                  setOpen(meal);
                }}
              />
            )}
          </View>
        );
      })}
      {notice ? <Caption>{notice}</Caption> : null}

      <Sheet visible={open !== null} onClose={() => setOpen(null)} title={`${openLabel} — what was served?`}>
        <Body muted>
          The posted menu keeps its promise; this records what actually happened, at the time.
        </Body>
        <Field value={served} onChangeText={setServed} placeholder="Vegetable soup with bread and milk" />
        <Field value={reason} onChangeText={setReason} placeholder="Why — delivery did not arrive…" />
        <Button label="Record — sign with PIN" onPress={() => void saveSubstitution()} />
        <Button label="Cancel" kind="quiet" onPress={() => setOpen(null)} />
      </Sheet>
    </Card>
  );
}

/** Parts 4 & 10 on the device that is actually outside: the day's due
 * compliance checks (playground walk, alarm test…) completed with a written
 * note and a PIN, right where the check happens. */
function ComplianceChecks() {
  const { getRecorder } = useRecorder();
  const [due, setDue] = useState<DueTask[]>([]);
  const [open, setOpen] = useState<DueTask | null>(null);
  const [note, setNote] = useState('');
  const [notice, setNotice] = useState<string | null>(null);

  const refresh = useCallback(() => {
    const today = new Date().toISOString().slice(0, 10);
    supabase
      .from('compliance_task')
      .select('id, title, regulation, next_due_on')
      .eq('active', true)
      .lte('next_due_on', today)
      .order('next_due_on')
      .then(({ data }) => setDue((data as DueTask[]) ?? []));
  }, []);
  useFocusEffect(refresh);

  async function complete() {
    if (!open) return;
    if (note.trim().length === 0) {
      setNotice('The note IS the written record — say what was done and found.');
      return;
    }
    const task = open;
    setOpen(null);
    const recorder = await getRecorder();
    if (!recorder) return;
    const result = await runCommand('complete_compliance_task', {
      p_task: task.id,
      p_note: note.trim(),
      p_completed_on: null,
      p_recorder: recorder.personId,
      p_pin: recorder.pin,
    });
    setNote('');
    setNotice(result.ok ? `${task.title} recorded.` : (result.error ?? 'Could not record — it will retry.'));
    refresh();
  }

  const today = new Date().toISOString().slice(0, 10);

  return (
    <Card wash={due.length > 0 ? 'sand' : 'mint'}>
      <Heading>Compliance checks</Heading>
      {due.length === 0 ? (
        <Body muted>Nothing due today — drills, inspections and tests are all on schedule.</Body>
      ) : (
        due.map((t) => (
          <View key={t.id} style={{ flexDirection: 'row', alignItems: 'center', gap: space.sm }}>
            <View style={{ flex: 1 }}>
              <Body>{t.title}</Body>
              <Caption>{t.regulation}</Caption>
            </View>
            <Pill kind={t.next_due_on < today ? 'now' : 'due'}>
              {t.next_due_on < today ? 'Overdue' : 'Due'}
            </Pill>
            <Button label="Done" kind="quiet" onPress={() => { setNote(''); setNotice(null); setOpen(t); }} />
          </View>
        ))
      )}
      {notice ? <Caption>{notice}</Caption> : null}

      <Sheet visible={open !== null} onClose={() => setOpen(null)} title={open?.title ?? ''}>
        <Body muted>What was done and what was found — this note is the written record.</Body>
        <Field
          value={note}
          onChangeText={setNote}
          placeholder="Walked the playground; surfaces clear, gate latch working…"
          multiline
        />
        <Button label="Record — sign with PIN" onPress={() => void complete()} />
        <Button label="Cancel" kind="quiet" onPress={() => setOpen(null)} />
      </Sheet>
    </Card>
  );
}

function MoreInner() {
  const { profile, setViewMode } = useAuth();
  return (
    <Screen>
      <Title>More</Title>
      {profile ? (
        <Card>
          <View style={{ flexDirection: 'row', alignItems: 'center', gap: space.md }}>
            <Avatar name={profile.fullName} size={44} />
            <View>
              <Heading>{profile.fullName}</Heading>
              <Caption>{profile.roles.map((r) => r.role.replace(/_/g, ' ')).join(' · ')}</Caption>
            </View>
          </View>
        </Card>
      ) : null}
      <TodaysMenu />
      <ComplianceChecks />
      <Card>
        <Heading>Records &amp; exports</Heading>
        <Body muted>
          Registers, corrections, staff files and per-section exports live in the supervisor
          console on the web.
        </Body>
      </Card>
      {profile?.dualRole ? (
        <Card wash="mist">
          <Heading>Your family view</Heading>
          <Body muted>You also have children enrolled here — see their day as a parent does.</Body>
          <Button label="Switch to Family view" kind="quiet" onPress={() => setViewMode('family')} />
        </Card>
      ) : null}
      <Button label="Session details" kind="quiet" onPress={() => router.push('/debug')} />
      <View style={{ marginTop: 'auto' }}>
        <Button label={enCA.auth.signOut} kind="quiet" onPress={() => supabase.auth.signOut()} />
      </View>
    </Screen>
  );
}

export default function More() {
  const [staff, setStaff] = useState<{ personId: string; fullName: string; role: string }[]>([]);
  useFocusEffect(
    useCallback(() => {
      loadRoomDay().then((d) => setStaff(d?.staff ?? []));
    }, []),
  );
  return (
    <RecorderProvider staff={staff}>
      <MoreInner />
    </RecorderProvider>
  );
}
