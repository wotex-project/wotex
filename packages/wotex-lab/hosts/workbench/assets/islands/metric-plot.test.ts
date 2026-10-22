import test from "node:test"
import assert from "node:assert/strict"
import {metricGeometry} from "./metric-plot.ts"

test("missing samples produce dotted bridges between actual endpoints without zero substitution",()=>{
  const series=[{name:"temperature",points:[[0,4],[1,null],[2,-2],[3,null]] as [number,number|null][]}]
  const before=JSON.stringify(series)
  const geometry=metricGeometry(series)
  assert.equal(geometry.missing,2)
  assert.equal(geometry.series[0].segments.length,2)
  assert.equal(geometry.series[0].bridges.length,1)
  assert.equal(geometry.series[0].dots.length,2)
  assert.equal(JSON.stringify(series),before)
  assert.equal(geometry.yTicks[0].value,-2)
  assert.equal(geometry.yTicks[2].value,4)
})

test("all-missing data stays unavailable and leading/trailing gaps invent no endpoints",()=>{
  const empty=metricGeometry([{name:"missing",points:[[0,null],[1,null]]}])
  assert.equal(empty.available,false)
  assert.deepEqual(empty.series[0].dots,[])
  assert.deepEqual(empty.series[0].bridges,[])
  const one=metricGeometry([{name:"one",points:[[0,null],[1,8],[2,null]]}])
  assert.equal(one.available,true)
  assert.equal(one.series[0].dots.length,1)
  assert.deepEqual(one.series[0].bridges,[])
  assert.ok(one.yTicks.every(t=>Number.isFinite(t.y)))
})

test("captured area marks use a zero baseline while preserving negative values and gaps",()=>{
  const series=[{name:"comparison",points:[[1,-4],[2,null],[3,-2]] as [number,number|null][]}]
  const before=JSON.stringify(series)
  const area=metricGeometry(series,"area")
  assert.equal(area.yTicks[0].value,-4)
  assert.equal(area.yTicks[2].value,0)
  assert.equal(area.series[0].areas.length,2)
  assert.equal(area.series[0].dots.length,2)
  assert.equal(JSON.stringify(series),before)
  assert.equal(metricGeometry([{name:"empty",points:[[0,null]]}],"area").available,false)
})
