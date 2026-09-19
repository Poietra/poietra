import type { Locale } from '../locale';
import { LandingPage as landing } from '../../../../_build/js/release/build/browser_site/browser_site.js';
import './LandingPage.css';

export interface LandingPageProps {
  locale: Locale;
  onStart: (template: 'blank' | 'example') => void;
  busy: 'blank' | 'example' | null;
  error: string;
  onCancel: () => void;
  resumeUrl: string | null;
}

export const LandingPage = landing as (props: LandingPageProps) => React.ReactElement;
