import type { Locale } from '../locale';
import './LandingPage.css';
export interface LandingPageProps {
    locale: Locale;
    onStart: (template: 'blank' | 'example') => void;
    busy: 'blank' | 'example' | null;
    error: string;
    onCancel: () => void;
    resumeUrl: string | null;
}
export declare const LandingPage: (props: LandingPageProps) => React.ReactElement;
