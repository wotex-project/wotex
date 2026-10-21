import type { MetricSeries } from "./canvas-model.js"

/** Missing samples stay null. Dotted bridges are visual annotations only. */
export function metricGeometry(series: MetricSeries[]) {
  const xs = series.flatMap(s => s.points.map(p => p[0]))
  const ys = series.flatMap(s => s.points.flatMap(p => p[1] === null ? [] : [p[1]]))
  const domain = (values: number[]) => {
    const lo=Math.min(...values), hi=Math.max(...values)
    if (!values.length) return [0,1]
    const pad=Math.max(Math.abs(lo)*0.05,1)
    return lo===hi ? [lo-pad,hi+pad] : [lo,hi]
  }
  const [x0,x1]=domain(xs), [y0,y1]=domain(ys)
  const sx=(x:number)=>42+(x-x0)/(x1-x0)*270
  const sy=(y:number)=>12+(y1-y)/(y1-y0)*112
  const xy=(p:[number,number])=>`${sx(p[0]).toFixed(2)},${sy(p[1]).toFixed(2)}`
  return {
    available: ys.length>0,
    missing: series.reduce((n,s)=>n+s.points.filter(p=>p[1]===null).length,0),
    xTicks:[x0,(x0+x1)/2,x1].map(v=>({value:v,x:sx(v)})),
    yTicks:[y0,(y0+y1)/2,y1].map(v=>({value:v,y:sy(v)})),
    series:series.map(s=>{
      const segments:string[]=[], bridges:string[]=[], dots:{x:number;y:number}[]=[]
      let segment:[number,number][]=[], previous:[number,number]|null=null, gap=false
      for(const [x,y] of s.points){
        if(y===null){
          if(segment.length)segments.push(segment.map(xy).join(" "))
          segment=[];gap=true
        } else {
          const point:[number,number]=[x,y]
          if(gap&&previous)bridges.push(`${xy(previous)} ${xy(point)}`)
          segment.push(point); previous=point;gap=false
          dots.push({x:sx(x),y:sy(y)})
        }
      }
      if(segment.length)segments.push(segment.map(xy).join(" "))
      return {name:s.name,segments,bridges,dots}
    })
  }
}

export function metricLabel(value:number):string {
  return new Intl.NumberFormat("en",{maximumSignificantDigits:3}).format(value)
}
