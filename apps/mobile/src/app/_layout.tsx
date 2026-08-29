import { useEffect } from 'react';
import { useFonts } from 'expo-font';
import { Stack } from 'expo-router';
import * as SplashScreen from 'expo-splash-screen';
import { StatusBar } from 'expo-status-bar';
import { colour } from '@tucked/ui-tokens';
import { AuthProvider } from '@/lib/auth';

SplashScreen.preventAutoHideAsync();

export default function RootLayout() {
  // Static instances, each under its own family name; select by fontFamily
  // only — never fontWeight (design-language.md §4). Baloo 2 = display
  // personality, Nunito = readable body.
  const [fontsLoaded] = useFonts({
    'Baloo2-SemiBold': require('@/assets/fonts/Baloo2-SemiBold.ttf'),
    'Baloo2-Bold': require('@/assets/fonts/Baloo2-Bold.ttf'),
    'Baloo2-ExtraBold': require('@/assets/fonts/Baloo2-ExtraBold.ttf'),
    'Nunito-Medium': require('@/assets/fonts/Nunito-Medium.ttf'),
    'Nunito-SemiBold': require('@/assets/fonts/Nunito-SemiBold.ttf'),
    'Nunito-Bold': require('@/assets/fonts/Nunito-Bold.ttf'),
  });

  useEffect(() => {
    if (fontsLoaded) SplashScreen.hideAsync();
  }, [fontsLoaded]);

  if (!fontsLoaded) return null;

  return (
    <AuthProvider>
      <StatusBar style="dark" />
      <Stack
        screenOptions={{
          headerShown: false,
          contentStyle: { backgroundColor: colour.canvas },
        }}
      />
    </AuthProvider>
  );
}
