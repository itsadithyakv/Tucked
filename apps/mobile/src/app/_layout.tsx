import { useEffect } from 'react';
import { useFonts } from 'expo-font';
import { Stack } from 'expo-router';
import * as SplashScreen from 'expo-splash-screen';
import { StatusBar } from 'expo-status-bar';
import { colour } from '@tucked/ui-tokens';
import { AuthProvider } from '@/lib/auth';

SplashScreen.preventAutoHideAsync();

export default function RootLayout() {
  // Gilroy ships as five internal families; load each under its family name and
  // select by fontFamily only — never fontWeight (design-language.md §4).
  const [fontsLoaded] = useFonts({
    'Gilroy-Light': require('@/assets/fonts/Gilroy-Light.ttf'),
    'Gilroy-Regular': require('@/assets/fonts/Gilroy-Regular.ttf'),
    'Gilroy-Medium': require('@/assets/fonts/Gilroy-Medium.ttf'),
    'Gilroy-Bold': require('@/assets/fonts/Gilroy-Bold.ttf'),
    'Gilroy-Heavy': require('@/assets/fonts/Gilroy-Heavy.ttf'),
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
