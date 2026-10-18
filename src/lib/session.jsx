import { createContext, useContext, useEffect, useState } from 'react'
import { supabase } from './supabase'

const SessionContext = createContext(null)

// Holds the signed-in user and their profile row (role and business).
export function SessionProvider({ children }) {
  const [session, setSession] = useState(undefined)
  const [profile, setProfile] = useState(null)

  useEffect(() => {
    supabase.auth.getSession().then(({ data }) => setSession(data.session))
    const { data } = supabase.auth.onAuthStateChange((_event, next) => setSession(next))
    return () => data.subscription.unsubscribe()
  }, [])

  useEffect(() => {
    if (!session) {
      setProfile(null)
      return
    }
    supabase
      .from('profiles')
      .select('id, business_id, role, full_name')
      .eq('id', session.user.id)
      .maybeSingle()
      .then(({ data }) => setProfile(data ?? false))
  }, [session])

  const value = {
    session,
    profile,
    loading: session === undefined || (session && profile === null),
    isStaff: profile && (profile.role === 'owner' || profile.role === 'admin'),
    signOut: () => supabase.auth.signOut(),
  }
  return <SessionContext.Provider value={value}>{children}</SessionContext.Provider>
}

export function useSession() {
  return useContext(SessionContext)
}
