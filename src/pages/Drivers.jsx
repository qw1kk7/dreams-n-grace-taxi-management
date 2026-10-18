import { useEffect, useState } from 'react'
import { supabase } from '../lib/supabase'
import { useSession } from '../lib/session'
import { formatDate, formatYears, yearsBetween } from '../lib/format'

const empty = { full_name: '', contact_number: '', address: '', license_number: '', license_expires_on: '', hire_date: '', notes: '' }

export default function Drivers() {
  const { profile } = useSession()
  const [drivers, setDrivers] = useState(null)
  const [form, setForm] = useState(empty)
  const [editingId, setEditingId] = useState(null)
  const [error, setError] = useState(null)

  async function load() {
    const { data, error } = await supabase
      .from('drivers')
      .select('*, driver_vehicle_assignments(end_date, vehicles(plate_number))')
      .order('full_name')
    if (error) setError(error.message)
    else setDrivers(data)
  }
  useEffect(() => { load() }, [])

  const set = (field) => (e) => setForm({ ...form, [field]: e.target.value })

  async function save(e) {
    e.preventDefault()
    setError(null)
    const row = Object.fromEntries(Object.entries(form).map(([k, v]) => [k, v === '' ? null : v]))
    const { error } = editingId
      ? await supabase.from('drivers').update(row).eq('id', editingId)
      : await supabase.from('drivers').insert({ ...row, business_id: profile.business_id })
    if (error) return setError(error.message)
    setForm(empty)
    setEditingId(null)
    load()
  }

  function edit(d) {
    setEditingId(d.id)
    setForm(Object.fromEntries(Object.keys(empty).map((k) => [k, d[k] ?? ''])))
  }

  async function setStatus(d, status) {
    if (status === 'terminated' && !confirm(`Mark ${d.full_name} as terminated?`)) return
    const { error } = await supabase.from('drivers').update({ status }).eq('id', d.id)
    if (error) setError(error.message)
    else load()
  }

  return (
    <>
      <h1>Drivers</h1>
      {error && <p className="error">{error}</p>}
      <div className="table-wrap"><table>
        <thead>
          <tr><th>Name</th><th>Contact</th><th>License</th><th>Hired</th><th>Service</th><th>Unit</th><th>Status</th><th /></tr>
        </thead>
        <tbody>
          {drivers === null && <tr><td colSpan="8" className="muted">Loading…</td></tr>}
          {(drivers ?? []).map((d) => {
            const current = d.driver_vehicle_assignments.find((a) => a.end_date == null)
            return (
              <tr key={d.id}>
                <td>{d.full_name}</td>
                <td>{d.contact_number}</td>
                <td>{d.license_number}{d.license_expires_on && <small> until {formatDate(d.license_expires_on)}</small>}</td>
                <td>{formatDate(d.hire_date)}</td>
                <td>{formatYears(yearsBetween(d.hire_date))}</td>
                <td>{current?.vehicles?.plate_number ?? <span className="muted">none</span>}</td>
                <td>
                  <select value={d.status} onChange={(e) => setStatus(d, e.target.value)} aria-label={`Status of ${d.full_name}`}>
                    <option value="active">Active</option>
                    <option value="inactive">Inactive</option>
                    <option value="terminated">Terminated</option>
                  </select>
                </td>
                <td><button className="link" onClick={() => edit(d)}>Edit</button></td>
              </tr>
            )
          })}
          {drivers?.length === 0 && <tr><td colSpan="8" className="muted">No drivers yet.</td></tr>}
        </tbody>
      </table></div>

      <form className="card" onSubmit={save}>
        <h2>{editingId ? 'Edit driver' : 'Add a driver'}</h2>
        <div className="grid">
          <label>Full name<input value={form.full_name} onChange={set('full_name')} required /></label>
          <label>Hire date<input type="date" value={form.hire_date} onChange={set('hire_date')} required /></label>
          <label>Contact number<input value={form.contact_number} onChange={set('contact_number')} /></label>
          <label>License number<input value={form.license_number} onChange={set('license_number')} /></label>
          <label>License expires<input type="date" value={form.license_expires_on} onChange={set('license_expires_on')} /></label>
          <label>Address<input value={form.address} onChange={set('address')} /></label>
        </div>
        <label>Notes<textarea value={form.notes} onChange={set('notes')} rows="2" /></label>
        <p className="muted">Years of service count from the hire date. They decide the Christmas and New Year discount.</p>
        <div className="actions">
          <button type="submit">{editingId ? 'Save changes' : 'Add driver'}</button>
          {editingId && <button type="button" className="secondary" onClick={() => { setEditingId(null); setForm(empty) }}>Cancel</button>}
        </div>
      </form>
    </>
  )
}
