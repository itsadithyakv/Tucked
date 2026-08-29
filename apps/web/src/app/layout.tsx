import type { Metadata } from 'next';
import '@tucked/ui-tokens/css/tokens.css';
import '@tucked/ui-tokens/css/fonts.css';
import './globals.css';

export const metadata: Metadata = {
  title: 'Tucked console',
  description: 'Supervisor and licensee console for Tucked.',
};

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="en-CA">
      <body>{children}</body>
    </html>
  );
}
