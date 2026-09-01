import type { Metadata } from 'next';
import '@tucked/ui-tokens/css/tokens.css';
import '@tucked/ui-tokens/css/fonts.css';
import './globals.css';

/* Runs before first paint: a supervisor who chose dark must never get a white
   flash at six in the morning. Deliberately tiny, inline and dependency-free —
   anything async would be too late to matter. */
const NO_FLASH = `try{var t=localStorage.getItem('tucked.theme');if(t==='dark'||t==='light'){document.documentElement.setAttribute('data-theme',t)}}catch(e){}`;

export const metadata: Metadata = {
  title: 'Tucked console',
  description: 'Supervisor and licensee console for Tucked.',
};

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="en-CA" suppressHydrationWarning>
      <head>
        <script dangerouslySetInnerHTML={{ __html: NO_FLASH }} />
      </head>
      <body>{children}</body>
    </html>
  );
}
