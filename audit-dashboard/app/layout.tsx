import type { Metadata } from 'next';
import { Geist, Geist_Mono } from 'next/font/google';
import './globals.css';

const geistSans = Geist({
  variable: '--font-geist-sans',
  subsets: ['latin'],
});

const geistMono = Geist_Mono({
  variable: '--font-geist-mono',
  subsets: ['latin'],
});

export const metadata: Metadata = {
  metadataBase: new URL('http://localhost:3000'),
  title: 'CardVault Audit Command Center',
  description:
    'An interactive remediation tracker for CardVault security, performance, APK size, dependencies, testing, and code quality findings.',
  openGraph: {
    title: 'CardVault Audit Command Center',
    description: 'Security · Performance · APK Size',
    images: [{ url: '/audit-social.png', width: 1662, height: 946, alt: 'CardVault Audit Command Center' }],
  },
  twitter: {
    card: 'summary_large_image',
    title: 'CardVault Audit Command Center',
    description: 'Security · Performance · APK Size',
    images: ['/audit-social.png'],
  },
};

export default function RootLayout({
  children,
}: Readonly<{
  children: React.ReactNode;
}>) {
  return (
    <html lang="en">
      <body
        className={`${geistSans.variable} ${geistMono.variable} antialiased`}
      >
        {children}
      </body>
    </html>
  );
}
