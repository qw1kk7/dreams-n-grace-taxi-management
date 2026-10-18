import { NavLink, Navigate, Route, Routes } from 'react-router-dom'
import { useSession } from './lib/session'
import Login from './pages/Login'
import Home from './pages/Home'
import Drivers from './pages/Drivers'
import Units from './pages/Units'
import Assignments from './pages/Assignments'
import Daily from './pages/Daily'

export default function App() {
  const { session, profile, loading, isStaff, signOut } = useSession()

  if (loading) return <p className="center muted">Loading…</p>
  if (!session) return <Login />
  if (profile === false) {
    return (
      <div className="center">
        <p>Your account is not linked to the business yet. Ask the owner to add you.</p>
        <button onClick={signOut}>Sign out</button>
      </div>
    )
  }
  if (!isStaff) {
    return (
      <div className="center">
        <h1>Hi, {profile.full_name}</h1>
        <p className="muted">The driver portal is coming in a later phase.</p>
        <button onClick={signOut}>Sign out</button>
      </div>
    )
  }

  return (
    <div className="shell">
      <header className="topbar">
        <strong className="brand">Dreams 'N Grace Taxi</strong>
        <nav>
          <NavLink to="/" end>Overview</NavLink>
          <NavLink to="/daily">Daily</NavLink>
          <NavLink to="/drivers">Drivers</NavLink>
          <NavLink to="/units">Units</NavLink>
          <NavLink to="/assignments">Assignments</NavLink>
        </nav>
        <span className="who">
          {profile.full_name} <button className="link" onClick={signOut}>Sign out</button>
        </span>
      </header>
      <main>
        <Routes>
          <Route path="/" element={<Home />} />
          <Route path="/daily" element={<Daily />} />
          <Route path="/drivers" element={<Drivers />} />
          <Route path="/units" element={<Units />} />
          <Route path="/assignments" element={<Assignments />} />
          <Route path="*" element={<Navigate to="/" />} />
        </Routes>
      </main>
    </div>
  )
}
