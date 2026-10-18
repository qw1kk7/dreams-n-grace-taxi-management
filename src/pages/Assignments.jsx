import { useEffect, useState } from 'react'
import { supabase } from '../lib/supabase'
import { useSession } from '../lib/session'
import { formatDate, today } from '../lib/format'

// The day before an ISO date, so an ended assignment and the next one never overlap.
const dayBefore = (iso) => {
  const d = new Date(`${iso}T00:00:00Z`)
  d.setUTCDate(d.getUTCDate() - 1)
  return d.toISOString().slice(0, 10)
}

export default function Assignments() {
  const { profile } = useSession()
  const [rows, setRows] = useState(null)
  const [drivers, setDrivers] = useState([])
  const [units, setUnits] = useState([])
  const [form, setForm] = useState({ driver_id: '', vehicle_id: '', start_date: today() })
  const [showHistory, setShowHistory] = useState(false)
  const [error, setError] = useState(null)

  async function load() {
    const [a, d, v] = await Promise.all([
      supabase.from('driver_vehicle_assignments')
        .select('*, drivers(full_name), vehicles(plate_number)')
        .order('start_date', { ascending: false }),
      supabase.from('drivers').select('id, full_name').eq('status', 'active').order('full_name'),
      supabase.from('vehicles').select('id, plate_number').neq('status', 'retired').order('plate_number'),
    ])
    const err = a.error ?? d.error ?? v.error
    if (err) return setError(err.message)
    setRows(a.data)
    setDrivers(d.data)
    setUnits(v.data)
  }
  useEffect(() => { load() }, [])

  const current = (rows ?? []).filter((r) => r.end_date == null)
  const busyDrivers = new Set(current.map((r) => r.driver_id))
  const busyUnits = new Set(current.map((r) => r.vehicle_id))

  async function assign(e) {
    e.preventDefault()
    setError(null)
    const { error } = await supabase
      .from('driver_vehicle_assignments')
      .insert({ ...form, business_id: profile.business_id })
    if (error) {
      return setError(error.code === '23P01'
        ? 'That driver or unit already has an assignment covering this date. End it first.'
        : error.message)
    }
    setForm({ driver_id: '', vehicle_id: '', start_date: today() })
    load()
  }

  async function end(r) {
    const last = prompt(`Last day ${r.drivers.full_name} drives ${r.vehicles.plate_number} (YYYY-MM-DD):`, dayBefore(today()))
    if (!last) return
    const { error } = await supabase.from('driver_vehicle_assignments').update({ end_date: last }).eq('id', r.id)
    if (error) setError(error.message)
    else load()
  }

  const shown = showHistory ? rows ?? [] : current

  return (
    <>
      <h1>Assignments</h1>
      <p className="muted">One driver per unit. Ending an assignment keeps it in the history.</p>
      {error && <p className="error">{error}</p>}
      <label className="inline">
        <input type="checkbox" checked={showHistory} onChange={(e) => setShowHistory(e.target.checked)} /> Show past assignments
      </label>
      <div className="table-wrap"><table>
        <thead><tr><th>Driver</th><th>Unit</th><th>From</th><th>Until</th><th /></tr></thead>
        <tbody>
          {shown.map((r) => (
            <tr key={r.id} className={r.end_date ? 'past' : ''}>
              <td>{r.drivers.full_name}</td>
              <td>{r.vehicles.plate_number}</td>
              <td>{formatDate(r.start_date)}</td>
              <td>{r.end_date ? formatDate(r.end_date) : 'current'}</td>
              <td>{!r.end_date && <button className="link" onClick={() => end(r)}>End</button>}</td>
            </tr>
          ))}
          {rows === null && <tr><td colSpan="5" className="muted">Loading…</td></tr>}
          {rows !== null && shown.length === 0 && <tr><td colSpan="5" className="muted">No assignments yet.</td></tr>}
        </tbody>
      </table></div>

      <form className="card" onSubmit={assign}>
        <h2>Assign a driver to a unit</h2>
        <div className="grid">
          <label>Driver
            <select value={form.driver_id} onChange={(e) => setForm({ ...form, driver_id: e.target.value })} required>
              <option value="">Choose…</option>
              {drivers.map((d) => <option key={d.id} value={d.id} disabled={busyDrivers.has(d.id)}>{d.full_name}{busyDrivers.has(d.id) ? ' (assigned)' : ''}</option>)}
            </select>
          </label>
          <label>Unit
            <select value={form.vehicle_id} onChange={(e) => setForm({ ...form, vehicle_id: e.target.value })} required>
              <option value="">Choose…</option>
              {units.map((u) => <option key={u.id} value={u.id} disabled={busyUnits.has(u.id)}>{u.plate_number}{busyUnits.has(u.id) ? ' (assigned)' : ''}</option>)}
            </select>
          </label>
          <label>Starting<input type="date" value={form.start_date} onChange={(e) => setForm({ ...form, start_date: e.target.value })} required /></label>
        </div>
        <div className="actions"><button type="submit">Assign</button></div>
      </form>
    </>
  )
}
