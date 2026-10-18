import { useEffect, useState } from 'react'
import { supabase } from '../lib/supabase'
import { useSession } from '../lib/session'
import { formatDate, formatPeso, today } from '../lib/format'

const reasonLabel = {
  sunday: 'Sunday 50% off',
  regular_holiday: 'Red-calendar holiday',
  special_holiday: 'Holiday',
  christmas_new_year: 'Christmas / New Year',
}

// When a payment is recorded for a past day, stamp it at noon of that day.
const receivedAt = (date) => (date === today() ? new Date().toISOString() : `${date}T12:00:00+08:00`)

export default function Daily() {
  const { profile } = useSession()
  const [date, setDate] = useState(today())
  const [rows, setRows] = useState(null)
  const [balances, setBalances] = useState([])
  const [flagged, setFlagged] = useState(new Set())
  const [message, setMessage] = useState(null)
  const [error, setError] = useState(null)

  async function load() {
    setError(null)
    const [a, o, b, f] = await Promise.all([
      supabase.from('driver_vehicle_assignments')
        .select('driver_id, vehicle_id, drivers(full_name), vehicles(plate_number)')
        .lte('start_date', date)
        .or(`end_date.is.null,end_date.gte.${date}`),
      supabase.from('daily_operations')
        .select('*, remittances(amount, method, collateral_item, received_at, profiles(full_name))')
        .eq('operation_date', date),
      supabase.from('driver_short_status').select('*').order('unpaid_since'),
      supabase.rpc('flagged_drivers', { p_as_of: today() }),
    ])
    const err = a.error ?? o.error ?? b.error ?? f.error
    if (err) return setError(err.message)
    const ops = new Map(o.data.map((op) => [op.vehicle_id, op]))
    setRows(a.data.map((as) => ({ ...as, op: ops.get(as.vehicle_id) })))
    setBalances(b.data)
    setFlagged(new Set(f.data.map((x) => x.driver_id)))
  }
  useEffect(() => { setRows(null); load() }, [date])

  async function openDay(row) {
    const { data, error } = await supabase.rpc('expected_boundary', {
      p_vehicle_id: row.vehicle_id, p_driver_id: row.driver_id, p_date: date,
    })
    if (error) return { error }
    const eb = data[0]
    return supabase.from('daily_operations').insert({
      business_id: profile.business_id,
      operation_date: date,
      vehicle_id: row.vehicle_id,
      driver_id: row.driver_id,
      boundary_rate_id: eb.boundary_rate_id,
      base_amount: eb.base_amount,
      day_discount: eb.day_discount,
      day_discount_reason: eb.day_discount_reason,
      created_by: profile.id,
    })
  }

  async function openAll() {
    setMessage(null)
    for (const row of rows.filter((r) => !r.op)) {
      const { error } = await openDay(row)
      if (error) { setError(error.message); break }
    }
    load()
  }

  async function closeDay() {
    if (!confirm(`Close ${formatDate(date)}? Drivers who remitted nothing get the ₱50 penalty.`)) return
    const { data, error } = await supabase.rpc('apply_no_remit_penalties', {
      p_business_id: profile.business_id, p_date: date,
    })
    if (error) return setError(error.message)
    setMessage(data === 0 ? 'Day closed. No penalties added.' : `Day closed. ${data} penalt${data === 1 ? 'y' : 'ies'} added.`)
    load()
  }

  async function pay({ driverId, opId, amount, method, item }) {
    const { error } = await supabase.from('remittances').insert({
      business_id: profile.business_id,
      driver_id: driverId,
      daily_operation_id: opId ?? null,
      amount,
      method,
      collateral_item: method === 'collateral' ? item : null,
      received_by: profile.id,
      received_at: receivedAt(date),
    })
    if (error) { setError(error.message); return false }
    load()
    return true
  }

  async function setExtra(op, name) {
    const { error } = await supabase.from('daily_operations').update({ extra_driver_name: name || null }).eq('id', op.id)
    if (error) setError(error.message)
  }

  const unopened = rows?.filter((r) => !r.op).length ?? 0
  const totals = (rows ?? []).reduce((t, r) => {
    if (!r.op) return t
    const paid = r.op.remittances.reduce((s, x) => s + Number(x.amount), 0)
    return { due: t.due + Number(r.op.amount_due), paid: t.paid + paid }
  }, { due: 0, paid: 0 })

  return (
    <>
      <h1>Daily remittances</h1>
      <div className="toolbar">
        <label className="inline">Day <input type="date" value={date} onChange={(e) => e.target.value && setDate(e.target.value)} /></label>
        {unopened > 0 && <button onClick={openAll}>Start the day for {unopened} unit{unopened === 1 ? '' : 's'}</button>}
        {rows?.length > 0 && unopened === 0 && <button className="secondary" onClick={closeDay}>Close the day</button>}
      </div>
      {message && <p className="notice">{message}</p>}
      {error && <p className="error">{error}</p>}

      {rows?.length > 0 && unopened === 0 && (
        <div className="stats">
          <div className="stat"><span>{formatPeso(totals.due)}</span>expected</div>
          <div className="stat"><span>{formatPeso(totals.paid)}</span>collected</div>
          <div className="stat"><span>{formatPeso(Math.max(totals.due - totals.paid, 0))}</span>short today</div>
        </div>
      )}

      <div className="table-wrap"><table>
        <thead><tr><th>Unit</th><th>Driver</th><th>Due</th><th>Paid</th><th>Short</th><th>Record payment</th></tr></thead>
        <tbody>
          {rows === null && <tr><td colSpan="6" className="muted">Loading…</td></tr>}
          {rows?.length === 0 && <tr><td colSpan="6" className="muted">No units were assigned on this day.</td></tr>}
          {rows?.map((r) => (
            <DayRow key={r.vehicle_id} row={r} flagged={flagged.has(r.driver_id)} onPay={pay} onExtra={setExtra} />
          ))}
        </tbody>
      </table></div>

      <h2 className="section">Outstanding balances</h2>
      <p className="muted">Shorts must be settled within 3 days. Flagged drivers are past that; what happens next is the owners' decision.</p>
      <div className="table-wrap"><table>
        <thead><tr><th>Driver</th><th>Balance</th><th>Unpaid since</th><th>Record settlement</th></tr></thead>
        <tbody>
          {balances.length === 0 && <tr><td colSpan="4" className="muted">Nobody owes anything.</td></tr>}
          {balances.map((b) => (
            <tr key={b.driver_id}>
              <td>{b.full_name} {flagged.has(b.driver_id) && <span className="badge">flagged</span>}</td>
              <td><strong>{formatPeso(b.balance)}</strong></td>
              <td>{formatDate(b.unpaid_since)}</td>
              <td><PaymentForm max={Number(b.balance)} onPay={(p) => pay({ ...p, driverId: b.driver_id })} /></td>
            </tr>
          ))}
        </tbody>
      </table></div>
    </>
  )
}

function DayRow({ row, flagged, onPay, onExtra }) {
  const { op } = row
  const [extra, setExtra] = useState(op?.extra_driver_name ?? '')
  useEffect(() => setExtra(op?.extra_driver_name ?? ''), [op?.extra_driver_name])

  if (!op) {
    return (
      <tr className="past">
        <td>{row.vehicles.plate_number}</td>
        <td>{row.drivers.full_name}</td>
        <td colSpan="4">Day not started</td>
      </tr>
    )
  }
  const paid = op.remittances.reduce((s, x) => s + Number(x.amount), 0)
  const short = Math.max(Number(op.amount_due) - paid, 0)
  return (
    <tr>
      <td><strong>{row.vehicles.plate_number}</strong></td>
      <td>
        {row.drivers.full_name} {flagged && <span className="badge">flagged</span>}
        <input
          className="extra" placeholder="Extra (extrador), if any" value={extra}
          onChange={(e) => setExtra(e.target.value)} onBlur={() => extra !== (op.extra_driver_name ?? '') && onExtra(op, extra)}
          aria-label={`Extra driver for ${row.vehicles.plate_number}`}
        />
      </td>
      <td>
        {formatPeso(op.amount_due)}
        {op.day_discount > 0 && <small> {reasonLabel[op.day_discount_reason]} (−{formatPeso(op.day_discount)})</small>}
      </td>
      <td>
        {formatPeso(paid)}
        {op.remittances.map((x, i) => (
          <small key={i}> {x.method === 'collateral' ? `collateral: ${x.collateral_item}` : ''} received by {x.profiles?.full_name}</small>
        ))}
      </td>
      <td className={short > 0 ? 'error' : ''}>{short > 0 ? formatPeso(short) : 'paid'}</td>
      <td>{short > 0 && <PaymentForm max={short} onPay={(p) => onPay({ ...p, driverId: row.driver_id, opId: op.id })} />}</td>
    </tr>
  )
}

function PaymentForm({ max, onPay }) {
  const [amount, setAmount] = useState('')
  const [method, setMethod] = useState('cash')
  const [item, setItem] = useState('')
  const [busy, setBusy] = useState(false)

  async function submit(e) {
    e.preventDefault()
    setBusy(true)
    const ok = await onPay({ amount: Number(amount), method, item })
    setBusy(false)
    if (ok) { setAmount(''); setItem(''); setMethod('cash') }
  }

  return (
    <form className="pay" onSubmit={submit}>
      <input type="number" min="1" step="1" max={max} placeholder={String(max)} value={amount}
        onChange={(e) => setAmount(e.target.value)} required aria-label="Amount" />
      <select value={method} onChange={(e) => setMethod(e.target.value)} aria-label="Method">
        <option value="cash">Cash</option>
        <option value="collateral">Collateral</option>
      </select>
      {method === 'collateral' && (
        <input placeholder="Item" value={item} onChange={(e) => setItem(e.target.value)} required aria-label="Collateral item" />
      )}
      <button type="submit" disabled={busy}>Record</button>
    </form>
  )
}
