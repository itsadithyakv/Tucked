import { useState } from 'react';
import { Image } from 'expo-image';
import { Redirect } from 'expo-router';
import { Pressable, StyleSheet, View } from 'react-native';
import { Feather } from '@expo/vector-icons';
import { enCA } from '@tucked/domain';
import { colour, space } from '@tucked/ui-tokens';
import { useAuth } from '@/lib/auth';
import { supabase } from '@/lib/supabase';
import { Body, Button, Caption, Card, Field, Screen, Title } from '@/ui/components';

export default function SignIn() {
  const { session } = useAuth();
  const [mode, setMode] = useState<'family' | 'staff'>('family');
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [showPassword, setShowPassword] = useState(false);
  const [busy, setBusy] = useState(false);
  const [notice, setNotice] = useState<string | null>(null);

  // Navigation is driven by auth state, not imperative router calls.
  if (session) return <Redirect href="/" />;

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
    }
    setBusy(false);
  }

  return (
    <Screen>
      <View style={styles.centre}>
        <View style={styles.column}>
          <Image
            source={require('@/assets/images/splash-icon.png')}
            style={styles.mark}
            accessibilityLabel="Tucked"
          />
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
              <View>
                <Field
                  placeholder="Password"
                  secureTextEntry={!showPassword}
                  value={password}
                  onChangeText={setPassword}
                  accessibilityLabel="Password"
                />
                <Pressable
                  accessibilityRole="button"
                  accessibilityLabel={showPassword ? 'Hide password' : 'Show password'}
                  onPress={() => setShowPassword((v) => !v)}
                  style={styles.eye}
                  hitSlop={10}
                >
                  <Feather name={showPassword ? 'eye-off' : 'eye'} size={20} color={colour.slateMuted} />
                </Pressable>
              </View>
            ) : null}
            <Button
              label={mode === 'family' ? enCA.auth.familySignInAction : enCA.auth.staffSignInAction}
              onPress={() => void submit()}
              busy={busy}
            />
            {notice ? <Body muted>{notice}</Body> : null}
          </Card>
          <Button
            label={mode === 'family' ? 'I work at a centre' : 'I am a parent'}
            kind="quiet"
            onPress={() => setMode(mode === 'family' ? 'staff' : 'family')}
          />
          <Caption>Demo: supervisor@ / educator@ / parent@mapleleaf.example · tucked-demo</Caption>
        </View>
      </View>
    </Screen>
  );
}

const styles = StyleSheet.create({
  centre: {
    flex: 1,
    justifyContent: 'center',
    alignItems: 'center',
  },
  column: {
    width: '100%',
    maxWidth: 420,
    gap: space.cardGap,
    alignItems: 'stretch',
  },
  mark: {
    width: 104,
    height: 104,
    alignSelf: 'center',
    marginBottom: space.sm,
  },
  eye: {
    position: 'absolute',
    right: space.base,
    top: 0,
    bottom: 0,
    justifyContent: 'center',
  },
});
