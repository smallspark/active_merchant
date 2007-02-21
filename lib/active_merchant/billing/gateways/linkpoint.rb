# Portions of the LinkPoint Gateway by Ryan Heneise
#--
# Copyright (c) 2005 Tobias Luetke
#
# Permission is hereby granted, free of charge, to any person obtaining
# a copy of this software and associated documentation files (the
# "Software"), to deal in the Software without restriction, including
# without limitation the rights to use, copy, modify, merge, publish,
# distribute, sublicense, and/or sell copies of the Software, and to
# permit persons to whom the Software is furnished to do so, subject to
# the following conditions:
#
# The above copyright notice and this permission notice shall be
# included in all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
# EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
# MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
# NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE
# LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION
# OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION
# WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
#++

require 'rexml/document'

module ActiveMerchant #:nodoc:
  module Billing #:nodoc:
    
    # Initialization Options
    # :login                Your store number
    # :pem                  The text of your linkpoint PEM file. Note
    #                       this is not the path to file, but its
    #                       contents. If you are only using one PEM
    #                       file on your site you can declare it 
    #                       globally and then you won't need to
    #                       include this option
    #
    #
    # A valid store number is required. Unfortunately, with LinkPoint 
    # YOU CAN'T JUST USE ANY OLD STORE NUMBER. Also, you can't just 
    # generate your own PEM file. You'll need to use a special PEM file 
    # provided by LinkPoint. 
    #
    # Go to http://www.linkpoint.com/support/sup_teststore.asp to set up 
    # a test account and obtain your PEM file.
    #
    # Declaring PEM file Globally
    # ActiveMerchant::Billing::LinkpointGateway.pem_file = File.read( File.dirname(__FILE__) + '/../mycert.pem' )
    # 
    # 
    # Valid Order Options
    # :result => 
    #   LIVE                  Production mode
    #   GOOD                  Approved response in test mode
    #   DECLINE               Declined response in test mode
    #   DUPLICATE             Duplicate response in test mode
    #                     
    # :ponumber               Order number
    #
    # :transactionorigin =>   Source of the transaction
    #    ECI                  Email or Internet
    #    MAIL                 Mail order
    #    MOTO                 Mail order/Telephone
    #    TELEPHONE            Telephone
    #    RETAIL               Face-to-face
    #
    # :ordertype =>       
    #    SALE                 Real live sale
    #    PREAUTH              Authorize only
    #    POSTAUTH             Forced Ticket or Ticket Only transaction
    #    VOID             
    #    CREDIT           
    #    CALCSHIPPING         For shipping charges calculations
    #    CALCTAX              For sales tax calculations
    #                     
    # Recurring Options   
    # :action =>          
    #    SUBMIT           
    #    MODIFY           
    #    CANCEL           
    #                     
    # :installments           Identifies how many recurring payments to charge the customer
    # :startdate              Date to begin charging the recurring payments. Format: YYYYMMDD or "immediate"
    # :periodicity  =>    
    #     MONTHLY         
    #     BIMONTHLY       
    #     WEEKLY          
    #     BIWEEKLY        
    #     YEARLY          
    #     DAILY           
    # :threshold              Tells how many times to retry the transaction (if it fails) before contacting the merchant.
    # :comments               Uh... comments
    #
    #
    # For reference: 
    #
    # https://www.linkpointcentral.com/lpc/docs/Help/APIHelp/lpintguide.htm
    #
    #  Entities = {
    #    :payment => [:subtotal, :tax, :vattax, :shipping, :chargetotal],
    #    :billing => [:name, :address1, :address2, :city, :state, :zip, :country, :email, :phone, :fax, :addrnum],
    #    :shipping => [:name, :address1, :address2, :city, :state, :zip, :country, :weight, :items, :carrier, :total],
    #    :creditcard => [:cardnumber, :cardexpmonth, :cardexpyear, :cvmvalue, :track],
    #    :telecheck => [:routing, :account, :checknumber, :bankname, :bankstate, :dl, :dlstate, :void, :accounttype, :ssn],
    #    :transactiondetails => [:transactionorigin, :oid, :ponumber, :taxexempt, :terminaltype, :ip, :reference_number, :recurring, :tdate],
    #    :periodic => [:action, :installments, :threshold, :startdate, :periodicity, :comments],
    #    :notes => [:comments, :referred]
    #  }
    #
    #
    # IMPORTANT NOTICE: 
    # 
    # LinkPoint's Items entity is not yet supported in this module.
    # 
    class LinkpointGateway < Gateway     
      attr_reader :response
      attr_reader :options
      
      # Your global PEM file. This will be assigned to you by linkpoint
      # 
      # Example: 
      # 
      # ActiveMerchant::Billing::LinkpointGateway.pem_file = File.read( File.dirname(__FILE__) + '/../mycert.pem' )
      # 
      cattr_accessor :pem_file
      
      TEST_URL  = 'https://staging.linkpt.net:1129/'
      LIVE_URL  = 'https://secure.linkpt.net:1129/'
           
      # @options = {
      #  :store_number => options[:login],
      #  :result => test? ? "GOOD" : "LIVE"
      # }.update(options)
      def initialize(options = {})
        requires!(options, :login)
        
        @options = {
          :result => 'LIVE'
        }.update(options)
        
        @pem = @options[:pem] || LinkpointGateway.pem_file
        
        raise ArgumentError, "You need to pass in your pem file using the :pem parameter or set it globally using ActiveMerchant::Billing::LinkpointGateway.pem_file = File.read( File.dirname(__FILE__) + '/../mycert.pem' ) or similar" if @pem.nil?
      end
      
      # Send a purchase request with periodic options
      # Recurring Options   
      # :action =>          
      #    SUBMIT           
      #    MODIFY           
      #    CANCEL           
      #                     
      # :installments           Identifies how many recurring payments to charge the customer
      # :startdate              Date to begin charging the recurring payments. Format: YYYYMMDD or "immediate"
      # :periodicity  =>    
      #     :monthly         
      #     :bimonthly       
      #     :weekly          
      #     :biweekly        
      #     :yearly          
      #     :daily           
      # :threshold              Tells how many times to retry the transaction (if it fails) before contacting the merchant.
      # :comments               Uh... comments
      #
      def recurring(money, creditcard, options={})
        requires!(options, [:periodicity, :bimonthly, :monthly, :biweekly, :weekly, :yearly, :daily], :installments, :order_id )
        
        options.update(
          :ordertype => "SALE",
          :action => "SUBMIT",
          :installments => options[:installments] || 12,
          :startdate => options[:startdate] || "immediate",
          :periodicity => options[:periodicity].to_s || "monthly",
          :comments => options[:comments] || nil,
          :threshold => options[:threshold] || 3
        )
        commit(money, creditcard, options)
      end
      
      # Buy the thing
      def purchase(money, creditcard, options={})
        requires!(options, :order_id)
        options.update(
          :ordertype => "SALE"
        )
        commit(money, creditcard, options)
      end
      
      #
      # Authorize the transaction
      # 
      # Reserves the funds on the customer's credit card, but does not charge the card.
      #
      def authorize(money, creditcard, options = {})
        requires!(options, :order_id)
        options.update(
          :ordertype => "PREAUTH"
        )
        commit(money, creditcard, options)
      end
      
      #
      # Post an authorization. 
      #
      # Captures the funds from an authorized transaction. 
      # Order_id must be a valid order id from a prior authorized transaction.
      # 
      def capture(money, authorization, options = {})
        options.update(
          :order_id => authorization,
          :ordertype => "POSTAUTH"
        )
        commit(money, nil, options)  
      end
      
      # Void a previous transaction
      def void(identification, options = {})
        options.update(
          :order_id => identification,
          :ordertype => "VOID"
        )
        commit(nil, nil, options)
      end
      
      # 
      # Refund an order
      # 
      # identification must be a valid order id previously submitted by SALE
      #
      def credit(money, identification, options = {})
        options.update(
          :ordertype => "CREDIT",
          :order_id => identification
        )
        commit(money, nil, options)
      end
      
      def self.supported_cardtypes
        [:visa, :master, :discover, :american_express]
      end
      
      def test?
        @options[:test] || Base.gateway_mode == :test
      end
      
      private
      
      # Commit the transaction by posting the XML file to the LinkPoint server
      def commit(money, creditcard, options = {})
        parameters = parameters(money, creditcard, options)
        
        if creditcard and result = test_result_from_cc_number(parameters[:creditcard][:cardnumber])
          return result
        end
        
        data = ssl_post post_data(parameters)
                
        @response = parse(data)
        
        success = (@response[:approved] == "APPROVED")
        message = response[:message]
        
        Response.new(success, message, @response, 
          :test => test?,
          :authorization => response[:ordernum]
        )
      end
      
      # Build the XML file
      def post_data(parameters = {})
        xml = REXML::Document.new
        order = xml.add_element("order")
        
        # Merchant Info
        merchantinfo = order.add_element("merchantinfo")
        merchantinfo.add_element("configfile").text = @options[:login]
        
        # Loop over the parameters hash to construct the XML string
        for key, value in parameters
          elem = order.add_element(key.to_s)
          for k, v in parameters[key]
            elem.add_element(k.to_s).text = parameters[key][k].to_s if parameters[key][k]
          end
          # Linkpoint doesn't understand empty elements: 
          order.delete(elem) if elem.size == 0
        end
        
        return xml.to_s
      end
      
      # Set up the parameters hash just once so we don't have to do it
      # for every action. 
      def parameters(money, creditcard, options = {})
        
        params = {
          :payment => {
            :subtotal => amount(options[:subtotal]),
            :tax => amount(options[:tax]),
            :vattax => amount(options[:vattax]),
            :shipping => amount(options[:shipping]),
            :chargetotal => amount(money)
          },
          :transactiondetails => {
            :transactionorigin => options[:transactionorigin] || "ECI",
            :oid => options[:order_id],
            :ponumber => options[:ponumber],
            :taxexempt => options[:taxexempt],
            :terminaltype => options[:terminaltype],
            :ip => options[:ip],
            :reference_number => options[:reference_number],
            :recurring => options[:recurring] || "NO",  #DO NOT USE if you are using the periodic billing option. 
            :tdate => options[:tdate]
          },
          :orderoptions => {
            :ordertype => options[:ordertype],
            :result => @options[:result]
          },
          :periodic => {
            :action => options[:action],
            :installments => options[:installments], 
            :threshold => options[:threshold], 
            :startdate => options[:startdate], 
            :periodicity => options[:periodicity], 
            :comments => options[:comments]
          },
          :telecheck => {
            :routing => options[:telecheck_routing],
            :account => options[:telecheck_account],
            :checknumber => options[:telecheck_checknumber],
            :bankname => options[:telecheck_bankname],
            :dl => options[:telecheck_dl],
            :dlstate => options[:telecheck_dlstate],
            :void => options[:telecheck_void],
            :accounttype => options[:telecheck_accounttype],
            :ssn => options[:telecheck_ssn],
          }
        }
      
        if creditcard
          params[:creditcard] = {
             :cardnumber => creditcard.number,
             :cardexpmonth => creditcard.month,
             :cardexpyear => format_creditcard_expiry_year(creditcard.year),
             :track => nil
          }
          
          if creditcard.verification_value?
            params[:creditcard][:cvmvalue] = creditcard.verification_value
            params[:creditcard][:cvmindicator] = 'provided'
          else
            params[:creditcard][:cvmindicator] = 'not_provided'
          end          
        end
        
        if billing_address = options[:billing_address] || options[:address]          
          
          params[:billing] = {}        
          params[:billing][:name]      = billing_address[:name] || creditcard ? creditcard.name : nil
          params[:billing][:address1]  = billing_address[:address1] unless billing_address[:address1].blank?
          params[:billing][:address2]  = billing_address[:address2] unless billing_address[:address2].blank?
          params[:billing][:city]      = billing_address[:city]     unless billing_address[:city].blank?
          params[:billing][:state]     = billing_address[:state]    unless billing_address[:state].blank?
          params[:billing][:zip]       = billing_address[:zip]      unless billing_address[:zip].blank?
          params[:billing][:country]   = billing_address[:country]  unless billing_address[:country].blank?
          params[:billing][:company]   = billing_address[:company]  unless billing_address[:company].blank?
          params[:billing][:phone]     = billing_address[:phone]  unless billing_address[:phone].blank?
          params[:billing][:email]     = options[:email] unless options[:email].blank?
        end                

        if shipping_address = options[:shipping_address] || billing_address  

          params[:shipping] = {}
          params[:shipping][:name]      = shipping_address[:name] || creditcard ? creditcard.name : nil
          params[:shipping][:address1]  = shipping_address[:address1] unless shipping_address[:address1].blank?
          params[:shipping][:address2]  = shipping_address[:address2] unless shipping_address[:address2].blank?
          params[:shipping][:city]      = shipping_address[:city]     unless shipping_address[:city].blank?
          params[:shipping][:state]     = shipping_address[:state]    unless shipping_address[:state].blank?
          params[:shipping][:zip]       = shipping_address[:zip]      unless shipping_address[:zip].blank?
          params[:shipping][:country]   = shipping_address[:country]  unless shipping_address[:country].blank?
        end        

        return params
      end
        
      def parse(xml)
        
        # For reference, a typical response...
        # <r_csp></r_csp>
        # <r_time></r_time>
        # <r_ref></r_ref>
        # <r_error></r_error>
        # <r_ordernum></r_ordernum>
        # <r_message>This is a test transaction and will not show up in the Reports</r_message>
        # <r_code></r_code>
        # <r_tdate>Thu Feb 2 15:40:21 2006</r_tdate>
        # <r_score></r_score>
        # <r_authresponse></r_authresponse>
        # <r_approved>APPROVED</r_approved>
        # <r_avs></r_avs>
        
        response = {:message => "Global Error Receipt", :complete => false}
        
        xml = REXML::Document.new("<response>#{xml}</response>")
        xml.root.elements.each do |node|
          response[node.name.downcase.sub(/^r_/, '').to_sym] = normalize(node.text)
        end unless xml.root.nil?
        
        response
      end
      
      # Redefine ssl_post to use our PEM file
      def ssl_post(data)
        
        raise "PEM file invalid or missing!" unless @pem =~ %r{RSA.*CERTIFICATE}m
        
        uri = URI.parse(test? ? TEST_URL : LIVE_URL)
        
        http = Net::HTTP.new(uri.host, uri.port) 
        
        http.verify_mode    = OpenSSL::SSL::VERIFY_NONE unless @ssl_strict
        http.use_ssl        = true
        http.cert           = OpenSSL::X509::Certificate.new(@pem)
        http.key            = OpenSSL::PKey::RSA.new(@pem)
        
        http.post(uri.path, data).body      
      end
    
      # Make a ruby type out of the response string
      def normalize(field)
        case field
        when "true"   then true
        when "false"  then false
        when ""       then nil
        when "null"   then nil
        else field
        end        
      end

      def format_creditcard_expiry_year(year)
        sprintf("%.4i", year)[-2..-1]
      end      
    end
  end
end