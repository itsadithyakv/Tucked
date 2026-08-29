import { useState } from 'react';
import { Image } from 'expo-image';
import { router } from 'expo-router';
import { View } from 'react-native';
import { enCA } from '@tucked/domain';
import { space } from '@tucked/ui-tokens';
import { supabase } from '@/lib/supabase';
import { Body, Button, Caption, Card, Field, Screen, Title } from '@/ui/components';

export default function SignIn() {
  const [mode, setMode] = useState<'family' | 'staff'>('family');
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [busy, setBusy] = useState(false);
  const [notice, setNotice] = useState<string | null>(null);

  async function submit() {
    setBusy(true);
    setNotice(null);
    if (mode === 'family') {
      const { error } = await supabase.auth.signInWithOtp({ email: email.trim() });
      setNotice(error ? enCA.errors.signInFailed : enCA.auth.familyLinkSent);
    } else {
      const { error } = await supabase.auth.signInWithPassword({
        email: email.trim(),
        password,
      });
      if (error) setNotice(enCA.errors.signInFailed);
      else router.replace('/');
    }
    setBusy(false);
  }

  return (
    <Screen>
      <View style={{ alignItems: 'center', paddingVertical: space.x2l }}>
        <Image
          source={require('@/assets/images/splash-icon.png')}
          style={{ width: 96, height: 96 }}
          accessibilityLabel="Tucked"
        />
      </View>
      <Card>
        <Title>{mode === 'family' ? enCA.auth.familySignInTitle : enCA.auth.staffSignInTitle}</Title>
        {mode === 'family' ? <Body muted>{enCA.auth.familySignInBody}</Body> : null}
        <Field
          placeholder="Email"
          keyboardType="email-address"
          value={email}
          onChangeText={setEmail}
          accessibilityLabel="Email"
        />
        {mode === 'staff' ? (
          <Field
            placeholder="Password"
            secureTextEntry
            value={password}
            onChangeText={setPassword}
            accessibilityLabel="Password"
          />
        ) : null}
        <Button
          label={mode === 'family' ? enCA.auth.familySignInAction : enCA.auth.staffSignInAction}
          onPress={submit}
          busy={busy}
        />
        {notice ? <Body muted>{notice}</Body> : null}
      </Card>
      <Button
        label={mode === 'family' ? 'I work at a centre' : 'I am a parent'}
        kind="quiet"
        onPress={() => setMode(mode === 'family' ? 'staff' : 'family')}
      />
      <Caption>Demo logins: supervisor@ / educator@ / parent@mapleleaf.example · tucked-demo</Caption>
    </Screen>
  );
}
