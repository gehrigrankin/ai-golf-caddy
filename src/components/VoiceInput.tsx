'use client';

import { useState, useRef, useCallback, useEffect } from 'react';
import { cn } from '@/lib/utils';

interface VoiceInputProps {
  onResult: (transcript: string) => void;
  disabled?: boolean;
  placeholder?: string;
}

export default function VoiceInput({ onResult, disabled, placeholder }: VoiceInputProps) {
  const [isListening, setIsListening] = useState(false);
  const [transcript, setTranscript] = useState('');
  const [textInput, setTextInput] = useState('');
  const [supported, setSupported] = useState(true);
  const recognitionRef = useRef<SpeechRecognition | null>(null);

  useEffect(() => {
    const SpeechRecognition =
      typeof window !== 'undefined'
        ? window.SpeechRecognition || window.webkitSpeechRecognition
        : null;

    if (!SpeechRecognition) {
      setSupported(false);
      return;
    }

    const recognition = new SpeechRecognition();
    recognition.continuous = false;
    recognition.interimResults = true;
    recognition.lang = 'en-US';

    recognition.onresult = (event: SpeechRecognitionEvent) => {
      const current = Array.from(event.results)
        .map((r) => r[0].transcript)
        .join('');
      setTranscript(current);

      if (event.results[event.results.length - 1].isFinal) {
        setIsListening(false);
        onResult(current);
        setTranscript('');
      }
    };

    recognition.onerror = () => {
      setIsListening(false);
    };

    recognition.onend = () => {
      setIsListening(false);
    };

    recognitionRef.current = recognition;
  }, [onResult]);

  const toggleListening = useCallback(() => {
    if (!recognitionRef.current) return;

    if (isListening) {
      recognitionRef.current.stop();
      setIsListening(false);
    } else {
      setTranscript('');
      recognitionRef.current.start();
      setIsListening(true);
    }
  }, [isListening]);

  const handleTextSubmit = (e: React.FormEvent) => {
    e.preventDefault();
    if (textInput.trim()) {
      onResult(textInput.trim());
      setTextInput('');
    }
  };

  return (
    <div className="space-y-3">
      {/* Voice button */}
      <button
        type="button"
        onClick={toggleListening}
        disabled={disabled || !supported}
        className={cn(
          'w-full flex items-center justify-center gap-3 py-4 px-6 rounded-2xl text-lg font-semibold transition-all',
          isListening
            ? 'bg-red-500 text-white shadow-lg shadow-red-500/30 animate-pulse'
            : 'bg-emerald-600 text-white hover:bg-emerald-700 active:scale-[0.98]',
          (disabled || !supported) && 'opacity-50 cursor-not-allowed'
        )}
      >
        <svg
          xmlns="http://www.w3.org/2000/svg"
          viewBox="0 0 24 24"
          fill="currentColor"
          className="w-6 h-6"
        >
          {isListening ? (
            <path d="M5.25 7.5A.75.75 0 016 6.75h12a.75.75 0 01.75.75v9a.75.75 0 01-.75.75H6a.75.75 0 01-.75-.75v-9z" />
          ) : (
            <path d="M8.25 4.5a3.75 3.75 0 117.5 0v8.25a3.75 3.75 0 11-7.5 0V4.5z" />
          )}
          {!isListening && (
            <path d="M6 10.5a.75.75 0 01.75.75 5.25 5.25 0 1010.5 0 .75.75 0 011.5 0 6.751 6.751 0 01-6 6.709v2.291h3a.75.75 0 010 1.5h-7.5a.75.75 0 010-1.5h3v-2.291a6.751 6.751 0 01-6-6.709.75.75 0 01.75-.75z" />
          )}
        </svg>
        {isListening ? 'Listening... Tap to stop' : 'Tap to speak'}
      </button>

      {/* Live transcript */}
      {transcript && (
        <div className="text-sm text-gray-400 italic text-center px-2">
          &quot;{transcript}&quot;
        </div>
      )}

      {/* Text fallback */}
      <form onSubmit={handleTextSubmit} className="flex gap-2">
        <input
          type="text"
          value={textInput}
          onChange={(e) => setTextInput(e.target.value)}
          placeholder={placeholder || 'Or type: "driver 250 fairway" ...'}
          disabled={disabled}
          className="flex-1 bg-gray-800 border border-gray-700 rounded-xl px-4 py-3 text-white placeholder-gray-500 focus:outline-none focus:ring-2 focus:ring-emerald-500/50"
        />
        <button
          type="submit"
          disabled={disabled || !textInput.trim()}
          className="bg-emerald-600 text-white px-5 py-3 rounded-xl font-medium hover:bg-emerald-700 disabled:opacity-50 disabled:cursor-not-allowed"
        >
          Go
        </button>
      </form>

      {!supported && (
        <p className="text-xs text-amber-400 text-center">
          Voice input not supported in this browser. Use text input instead.
        </p>
      )}
    </div>
  );
}
