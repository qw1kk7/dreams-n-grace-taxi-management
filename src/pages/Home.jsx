import { useEffect, useState } from 'react'
import { Link } from 'react-router-dom'
import { supabase } from '../lib/supabase'

export default function Home() {
  const [counts, setCounts] = useState(null)

  useEffect(() => {
    const count = (table, filter) => {
      let q = supabase.from(table).select('id', { count: 'exact', head: true })
      if (filter) q = filter(q)
      return q.then(({ count }) => count ?? 0)
    }
    Promise.all([
      count('drivers', (q) => q.eq('status', 'active')),
      count('vehicles', (q) => q.neq('status', 'retired')),
      count('driver_vehicle_assignments', (q) => q.is('end_date', null)),
    ]).then(([drivers, units, assigned]) => setCounts({ drivers, units, assigned }))
  }, [])

  if (!counts) return <p className="muted">Loading…</p>
  const unassigned = counts.units - counts.assigned

  return (
    <>
      <h1>Overview</h1>
      <div className="stats">
        <Link to="/drivers" className="stat"><span>{counts.drivers}</span>active drivers</Link>
        <Link to="/units" className="stat"><span>{counts.units}</span>units in service</Link>
        <Link to="/assignments" className="stat"><span>{counts.assigned}</span>units assigned</Link>
      </div>
      {unassigned > 0 && (
        <p className="notice">{unassigned} unit{unassigned === 1 ? ' has' : 's have'} no driver. <Link to="/assignments">Assign a driver</Link></p>
      )}
      <p className="muted">Daily remittances and reports come next.</p>
    </>
  )
}
