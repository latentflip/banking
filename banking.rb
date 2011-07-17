require 'rubygems'
require 'ofx-parser'
require 'yaml'
require 'active_support'
require 'active_support/all'
require 'ruport'



statements = Dir.glob('statements/*')

class Array
  def uniq_by(&blk)
    transforms = []
    self.select do |el|
      should_keep = !transforms.include?(t=blk[el])
      transforms << t
      should_keep
    end
  end
end





class Month
  attr_accessor :date, :entries

  def initialize(date, entries)
    @date ||= date.to_date
    @entries ||= entries.uniq_by {|e| e.fit_id}
  end

  def ins
    Month.new(
      self.date, 
      entries.select {|e| BigDecimal.new(e.amount) > 0}
    )
  end
  def outs
    Month.new(
      self.date,
      entries.select {|e| BigDecimal.new(e.amount) <= 0} )
  end

  def total_spend
    entries.inject(BigDecimal.new('0')) {|s,e| s += BigDecimal.new(e.amount) }
  end

  def transactions_to_s
    entries.map { |e|
      "#{e.date.to_s} \t #{e.payee} \t #{e.amount}"
    }
  end
end


class Report
  def initialize
    @months ||= []
  end
  def months
    @months
  end
  def monthly_spend(in_out)
    spend = {}
    @months.map do |m|
      spend[m.date] = m.send(in_out).total_spend
    end
    spend
  end
  def transactions(in_out)
    transactions = {}
    @months.map do |m|
      transactions[m.date.to_date] = m.send(in_out).transactions_to_s
    end
    transactions
  end
end

transactions = []
statements.each do |s|
  ofx = OfxParser::OfxParser.parse(open(s))
  transactions += ofx.bank_account.statement.transactions
end
transactions = transactions.uniq_by {|t| t.fit_id}


clean_up = {
  /^singer hc$/i => :end_of_month,
  /^o2$/i => :end_of_month
}

def shift_date_to(date, shift)
  dates = [-1,0,1].map do |offset|
    (date >> offset).send(shift)
  end
  dates.min_by {|d| (date - d).abs}
end

clean_up.each do |r, shift|
  ts = transactions.select {|t| t.payee =~ r}
  ts.each do |t|
    index = transactions.index(t)
    t.date = shift_date_to(t.date, shift)
    transactions[index] = t
  end
end




#Fill in table headers
start_date = transactions.sort_by {|t| t.date}.first.date.beginning_of_month
end_date = transactions.sort_by {|t| t.date}.last.date.beginning_of_month

headers = ['name', start_date.to_date.to_s]
while start_date < end_date
  start_date = start_date >> 1
  headers << start_date.to_date.to_s
end
headers << 'average'
n_months = headers.size - 2

fixed_table = Table(*headers)
random_table = Table(*headers)

groups = transactions.group_by {|t| t.payee }

merge_if = {
  'Cash' => /^CASH/,
  'Eating Out' => [/^LOUDONS/, /^STARBUCKS/, /^ILLEGAL/, /^FILMHOUSE/, /^HUMMUS BROTHERS LT/, /BONSAI BAR BISTRO/],
  'Groceries' => [/^TESCO/, /^SCOTMID/, /^SAINSBURYS/, /^MARGIOTTA/, /^REAL FOODS/],
  'Drinks' => [/^ECHO BAR/, /^CAMEO/],
  'Travel' => [/^FIRST SCOTRAIL/, /^EC MAINLINE/],
  'Computer Stuff' => [/ITUNES/, /PAYPAL/]

}


merge_if.each do |name,search|
  search = [search].flatten #turn into array if not already
  matching = search.map {|r| groups.keys.grep(r)}.uniq.flatten

  new_list = []
  matching.each do |m|
    new_list += groups.delete(m)
  end
  groups[name] = new_list
end




new_groups = {}
groups.each do |title,transactions|
  if transactions.size == 1 && transactions[0].amount.to_f.abs < 30
    new_groups['misc'] ||= []
    new_groups['misc'] += transactions
  else
    new_groups[title] = transactions
  end
end

ignore = [
  /^400125 01280082$/,
  /^CHQ  IN AT 402054$/i,
  /^wolfson micro/i
]
fixed = [
  /^keith potts$/i,
  /^edinburgh council$/i,
  /^scottishpower plc$/i,
  /^hsbc credit card$/i,
  /^o2$/i,
  /^virgin media pymts$/i,
  /^singer hc$/i
]


new_groups.each do |title, transactions|
  unless ignore.any? {|r| r=~title}
    row = {'name' => title}


    g = transactions.group_by {|t| t.date.to_date.beginning_of_month.to_s}
    g.each do |m,entries|
      str = entries.inject(BigDecimal.new('0')) {|s,e| s+=BigDecimal.new(e.amount)}
      #str = str.to_s + " (#{entries.size})" unless entries.size==1
      row[m] = str
    end
    
    if fixed.any? {|r| r=~ row['name']}
      row['average'] = (transactions.inject(BigDecimal.new('0')) {|s,e| s+= BigDecimal.new(e.amount)}/n_months).floor
      fixed_table << row
    else
      row['average'] = (transactions.inject(BigDecimal.new('0')) {|s,e| s+= BigDecimal.new(e.amount)}/n_months).floor
      random_table << row
    end
  end
end

def sum_columns(table, headers)
  total_row = {'name' => 'Total'}
  headers[1..-1].each do |h|
    total_row[h] = table.sum(h)
  end
  table << total_row
end


fixed_table.sort_rows_by! {|r| r['average']}
random_table.sort_rows_by! {|r| r['average']}

sum_columns(fixed_table, headers)
sum_columns(random_table, headers)

puts fixed_table
puts random_table

