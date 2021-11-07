[CmdletBinding()]
param (
    [Parameter(Mandatory)]
    [int]$days
)

Connect-AzAccount

$et=Get-Date
$st=$et.AddDays(-$days)

$result=@()
foreach($line in Get-Content -Path ./subs.txt){
    Set-AzContext -Subscription $line
    $subscription=Get-AzSubscription -SubscriptionId $line | Select-Object -ExpandProperty Name
    $vms = Get-AzVM
    foreach($vm in $vms){
        $cpu_total=0.0
        $memory_total=0.0
        $cpu = Get-AzMetric -ResourceId $vm.Id -MetricName "Percentage CPU" -DetailedOutput -StartTime $st -EndTime $et -TimeGrain 12:00:00  -WarningAction SilentlyContinue
        $memory = Get-AzMetric -ResourceId $vm.Id -MetricName "Available Memory Bytes" -DetailedOutput -StartTime $st -EndTime $et -TimeGrain 12:00:00  -WarningAction SilentlyContinue
        foreach ($c in $cpu.Data.Average) {
            $cpu_total += $c
        }
        foreach ($m in $memory.Data.Average) {
            $memory_total += $m
        }
        $cpu_total = $cpu_total/6
        $memory_total = $memory_total/(2 * 1000 * 1024 * $days)

        $details = @{
            resourcegroup = $vm.ResourceGroupName
            name = $vm.Name
            size = $vm.HardwareProfile.VmSize
            subscription = $subscription
            averagecpu = $cpu_total
            availablememory = $memory_total
        }
        $result += New-Object PSObject -Property $details
    }
}

$result | Export-Csv -Path ".\cpumetrics.csv"
