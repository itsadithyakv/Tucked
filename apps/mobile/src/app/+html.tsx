import { ScrollViewStyleReset } from 'expo-router/html';
import type { PropsWithChildren } from 'react';

/** Web-only document shell: constrain the height chain so screens scroll
 * inside themselves and the tab bar pins to the viewport — matching how the
 * native app behaves. */
export default function Root({ children }: PropsWithChildren) {
  return (
    <html lang="en-CA">
      <head>
        <meta charSet="utf-8" />
        <meta httpEquiv="X-UA-Compatible" content="IE=edge" />
        <meta name="viewport" content="width=device-width, initial-scale=1, shrink-to-fit=no, viewport-fit=cover" />
        <ScrollViewStyleReset />
        <style dangerouslySetInnerHTML={{ __html: 'html, body, #root { height: 100%; overflow: hidden; } #root { display: flex; }' }} />
      </head>
      <body>{children}</body>
    </html>
  );
}
