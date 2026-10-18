import { useEffect, useState } from 'react'
import { supabase } from '../lib/supabase'
import { useSession } from '../lib/session'
import { formatDate, formatYears, formatPeso, rateForAge, today, yearsBetween } from '../lib/format'

const empty = { plate_number: '', unit_number: '', make: '', model: '', first_registered_on: '', registration_expires_on: '' }

export default function Units() {
  const { profile } = useSession()
  const [units, setUnits] = useState(null)
  const [rates, setRates] = useState(null)
  const [form, setForm] = useState(empty)
  const [editingId, setEditingId] = useState(null)
  const [error, setError] = useState(null)

  async function load() {
    const [u, r] = await Promise.all([
      supabase.from('vehicles').select('*, driver_vehicle_assignments(end_date, drivers(full_name))').order('plate_number'),
      supabase.from('boundary_rates').select('*'),
    ])
    if (u.error || r.error) return setError((u.error ?? r.error).message)
    setUnits(u.data)
    setRates(r.data)
  }
  useEffect(() => { load() }, [])

  const set = (field) => (e) => setForm({ ...form, [field]: e.target.value })

  async function save(e) {
    e.preventDefault()
    setError(null)
    const row = Object.fromEntries(Object.entries(form).map(([k, v]) => [k, v === '' ? null : v]))
    const { error } = editingId
      ? await supabase.from('vehicles').update(row).eq('id', editingId)
      : await supabase.from('vehicles').insert({ ...row, business_id: profile.business_id })
    if (error) return setError(error.code === '23505' ? 'A unit with that plate number already exists.' : error.message)
    setForm(empty)
    setEditingId(null)
    load()
  }

  function edit(u) {
    setEditingId(u.id)
    setForm(Object.fromEntries(Object.keys(empty).map((k) => [k, u[k] ?? ''])))
  }

  async function setStatus(u, status) {
    const { error } = await supabase.from('vehicles').update({ status }).eq('id', u.id)
    if (error) setError(error.message)
    else load()
  }

  return (
    <>
      <h1>Units</h1>
      {rates?.length === 0 && <p className="notice">No boundary rates are set up yet, so daily rent can't be worked out.</p>}
      {error && <p className="error">{error}</p>}
      <div className="table-wrap"><table>
        <thead>
          <tr><th>Plate</th><th>Unit</th><th>Make and model</th><th>Age</th><th>Daily boundary</th><th>Registration</th><th>Driver</th><th>Status</th><th /></tr>
        </thead>
        <tbody>
          {units === null && <tr><td colSpan="9" className="muted">Loading…</td></tr>}
          {(units ?? []).map((u) => {
            const age = yearsBetween(u.first_registered_on)
            const rate = rateForAge(rates ?? [], age)
            const driver = u.driver_vehicle_assignments.find((a) => a.end_date == null)?.drivers?.full_name
            const regDue = u.registration_expires_on && u.registration_expires_on < today()
            return (
              <tr key={u.id}>
                <td><strong>{u.plate_number}</strong></td>
                <td>{u.unit_number}</td>
                <td>{[u.make, u.model].filter(Boolean).join(' ')}</td>
                <td>{formatYears(age)}</td>
                <td>{rate ? formatPeso(rate.daily_amount) : <span className="error">no rate</span>}</td>
                <td className={regDue ? 'error' : ''}>{formatDate(u.registration_expires_on)}{regDue && ' (overdue)'}</td>
                <td>{driver ?? <span className="muted">none</span>}</td>
                <td>
                  <select value={u.status} onChange={(e) => setStatus(u, e.target.value)} aria-label={`Status of ${u.plate_number}`}>
                    <option value="active">Active</option>
                    <option value="in_maintenance">In maintenance</option>
                    <option value="retired">Retired</option>
                  </select>
                </td>
                <td><button className="link" onClick={() => edit(u)}>Edit</button></td>
              </tr>
            )
          })}
          {units?.length === 0 && <tr><td colSpan="9" className="muted">No units yet.</td></tr>}
        </tbody>
      </table></div>

      <form className="card" onSubmit={save}>
        <h2>{editingId ? 'Edit unit' : 'Add a unit'}</h2>
        <div className="grid">
          <label>Plate number<input value={form.plate_number} onChange={set('plate_number')} required /></label>
          <label>Unit number<input value={form.unit_number} onChange={set('unit_number')} /></label>
          <label>Make<input value={form.make} onChange={set('make')} /></label>
          <label>Model<input value={form.model} onChange={set('model')} /></label>
          <label>First registered<input type="date" value={form.first_registered_on} onChange={set('first_registered_on')} required /></label>
          <label>Registration expires<input type="date" value={form.registration_expires_on} onChange={set('registration_expires_on')} /></label>
        </div>
        <p className="muted">The unit's age counts from its first registration. Under 5 years pays the higher boundary.</p>
        <div className="actions">
          <button type="submit">{editingId ? 'Save changes' : 'Add unit'}</button>
          {editingId && <button type="button" className="secondary" onClick={() => { setEditingId(null); setForm(empty) }}>Cancel</button>}
        </div>
      </form>
    </>
  )
}
