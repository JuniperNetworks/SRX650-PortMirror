<?xml version="1.0" standalone="yes"?>
<xsl:stylesheet version="1.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform" 
  xmlns:junos="http://xml.juniper.net/junos/*/junos" 
  xmlns:xnm="http://xml.juniper.net/xnm/1.1/xnm" 
  xmlns:ext="http://xmlsoft.org/XSLT/namespace" 
  xmlns:jcs="http://xml.juniper.net/junos/commit-scripts/1.0" 
  xmlns:func="http://exslt.org/functions" xmlns:dyn="http://exslt.org/dynamic" 
  xmlns:local="http://xml.juniper.net/local" 
  extension-element-prefixes="dyn func">
  <xsl:import href="../import/junos.xsl"/>
    
    
  <!-- Global vairable declarations -->
  <xsl:variable name="arguments">
    <argument>
      <name>output-port</name>
      <description>Mirror port where packets are copied to</description>
    </argument>
    <argument>
      <name>input-ingress</name>
      <description>Comma separated list of ports to mirror (for traffic in the ingress direction)</description>
    </argument>
    <argument>
      <name>input-egress</name>
      <description>Comma separated list of ports to mirror (for traffic in the egress direction)</description>
    </argument>
    <argument>
      <name>action</name>
      <description>Enable or disable</description>
    </argument>
  </xsl:variable>
  
  <!-- Embeded event policy -->
  <xsl:variable name="event-definition">
    <event-options>
      <policy>
        <name>port-mirror</name>
        <events>ui_commit_progress</events>
        <attributes-match>
          <from-event-attribute>ui_commit_progress.message</from-event-attribute>
          <condition>matches</condition>
          <to-event-attribute-value>signaling 'Ethernet Switching Process'</to-event-attribute-value>
        </attributes-match>
        <then>
          <event-script>
            <name>port-mirror.xslt</name>
          </event-script>
        </then>
      </policy>
      <policy>
        <name>reboot</name>
        <events>chassisd_snmp_trap10</events>
        <then>
          <event-script>
            <name>port-mirror.xslt</name>
          </event-script>
        </then>
      </policy>
    </event-options>
  </xsl:variable>

  <!-- 
    <configuration>
      <ethernet-switching-options>
        <apply-macro>
          <name>port-mirror</name>
          <data>
            <name>input-egress</name>
            <value>ge-2/0/0</value>
          </data>
          <data>
            <name>input-ingress</name>
            <value>ge-2/0/0</value>
          </data>
          <data>
            <name>output</name>
            <value>ge-2/0/8</value>
          </data>
       </apply-macro>
    </ethernet-switching-options>
  </configuration>  
-->
  
  <!-- Open a persistant connection -->
  <xsl:variable name="connection" select="jcs:open()"/>
  <xsl:variable name="get-config-rpc">
    <rpc>
      <get-configuration>
        <configuration>
          <ethernet-switching-options>
              <apply-macro/>
          </ethernet-switching-options>
        </configuration>
      </get-configuration>
    </rpc>
  </xsl:variable>
  <xsl:variable name="port-mirror-config" select="jcs:execute($connection, $get-config-rpc)"/>
  <xsl:param name="output-port" select="$port-mirror-config//ethernet-switching-options/apply-macro[name='port-mirror']/data[name='output-port']/value"/>
  <xsl:param name="input-ingress" select="$port-mirror-config//ethernet-switching-options/apply-macro[name='port-mirror']/data[name='input-ingress']/value"/>
  <xsl:param name="input-egress" select="$port-mirror-config//ethernet-switching-options/apply-macro[name='port-mirror']/data[name='input-egress']/value"/>
  <xsl:param name="action">
    <xsl:choose>
      <xsl:when test="jcs:empty($output-port)">disable</xsl:when>
      <xsl:otherwise>enable</xsl:otherwise>
    </xsl:choose>
  </xsl:param>
  
  <!-- Function declarations -->
  <func:function name="local:ifd-to-port">
    <xsl:param name="ifd"/>
    <xsl:variable name="ifd-parse" select="jcs:regex('ge-(.+)/0/(.+)',$ifd)"/>
    <xsl:variable name="port" select="$ifd-parse[3]"/>
    <xsl:choose>
      <xsl:when test="jcs:empty($ifd-parse[1])">
        <func:result/>
      </xsl:when>
      <xsl:when test="$port &lt; 0 or $port &gt; 23">
        <func:result/>
      </xsl:when>
      <xsl:when test="($port mod 2) = 0">
        <func:result select="concat('ge', $port + 1)"/>
      </xsl:when>
      <xsl:otherwise>
        <func:result select="concat('ge', $port - 1)"/>
      </xsl:otherwise>
    </xsl:choose>
  </func:function>

  <func:function name="local:ifdlist-to-portlist">
    <xsl:param name="ifdlist"/>
  
    <xsl:choose>
 
      <xsl:when test="jcs:empty($ifdlist)">
        <func:result><xsl:text>0x0</xsl:text></func:result>
      </xsl:when>
 
      <xsl:otherwise>
        <xsl:variable name="ifds" select="jcs:split(',',$ifdlist)"/>
        <xsl:variable name="port-list">
          <xsl:for-each select="$ifds">
            <xsl:value-of select="local:ifd-to-port(.)"/>
            <xsl:if test="position()!=last()">
              <xsl:text>,</xsl:text>
            </xsl:if>
          </xsl:for-each>
        </xsl:variable>    
        <func:result select="$port-list"/>
      </xsl:otherwise>

    </xsl:choose>
  </func:function>

  <func:function name="local:ifd-to-slot">
    <xsl:param name="ifd"/>
    <xsl:variable name="ifd-parse" select="jcs:regex('ge-(.+)/0/(.+)',$ifd)"/>
    <xsl:choose>
      <xsl:when test="$ifd-parse[2] &gt; 0 and $ifd-parse[2] &lt; 9">
        <func:result select="$ifd-parse[2]"/>
      </xsl:when>
      <xsl:otherwise>
        <func:result/>
      </xsl:otherwise>
    </xsl:choose>
  </func:function>

  <func:function name="local:pfe-push">
    <xsl:param name="connection"/>
    <xsl:param name="command"/>
    
    <xsl:variable name="pfe-exec-rpc">
      <rpc>
        <request-pfe-execute>
          <target>fwdd</target>
          <command><xsl:value-of select="$command"/></command>
        </request-pfe-execute>
      </rpc>
    </xsl:variable>
    <xsl:variable name="pfe-exec-result" select="jcs:execute($connection, $pfe-exec-rpc)"/>
    <func:result><xsl:value-of select="$pfe-exec-result"/></func:result>
  </func:function>

  <!-- Main -->
  <xsl:template match="/">
    <op-script-results>
      
      <!-- We are all good, push the config -->
    <xsl:choose>
      <!-- Enable Port mirroring -->
      <xsl:when test="$action = 'enable'">
        <xsl:value-of select="local:pfe-push($connection,concat(
          'set jbcm slot ', local:ifd-to-slot($output-port)
          ))"/>
        <xsl:value-of select="jcs:sleep(3,000)"/>
        <xsl:value-of select="local:pfe-push($connection, concat(
          'set jbcm command &quot; Mirror Mode=L2 Port=', local:ifd-to-port($output-port), 
          '&quot;'
          ))"/>
        <xsl:value-of select="jcs:sleep(3,000)"/>
        <xsl:value-of select="local:pfe-push($connection, concat(
          'set jbcm command &quot;Mirror ', 
          'IngressBitMap=', local:ifdlist-to-portlist($input-ingress),  
          '&quot;'
          ))"/>
        <xsl:value-of select="jcs:sleep(3,000)"/>
        <xsl:value-of select="local:pfe-push($connection, concat(
          'set jbcm command &quot;Mirror ', 
          'EgressBitMap=', local:ifdlist-to-portlist($input-egress), 
          '&quot;'
          ))"/>
        <xsl:value-of select="jcs:sleep(3,000)"/>
        <output>
          <xsl:copy-of select="jcs:printf('Port mirroring enabled\n')"/>
        </output>
      </xsl:when>
      
      <!-- Disable port mirroring, because we don't know when was configured we just send to command to the only two possible slots -->
      <xsl:when test="$action = 'disable'">
        <xsl:value-of select="jcs:sleep(3,000)"/>
        <xsl:value-of select="local:pfe-push($connection,'set jbcm slot 2')"/>
        <xsl:value-of select="jcs:sleep(3,000)"/>
        <xsl:value-of select="local:pfe-push($connection,'set jbcm command &quot;mirror Mode=off &quot;')"/>
        <xsl:value-of select="jcs:sleep(3,000)"/>
        <xsl:value-of select="local:pfe-push($connection,'set jbcm slot 6')"/>
        <xsl:value-of select="jcs:sleep(3,000)"/>
        <xsl:value-of select="local:pfe-push($connection,'set jbcm command &quot;mirror Mode=off &quot;')"/>
        <xsl:value-of select="jcs:sleep(3,000)"/>
        <output>
          <xsl:copy-of select="jcs:printf('Port mirroring disabled\n')"/>
        </output>
      </xsl:when>
      
      <!-- Show the config -->
      <xsl:otherwise>
      <output>
        <xsl:value-of select="jcs:sleep(3,000)"/>
        <xsl:value-of select="local:pfe-push($connection,'set jbcm slot 2')"/>
        <xsl:value-of select="jcs:sleep(3,000)"/>
        <xsl:value-of select="local:pfe-push($connection,'set jbcm command &quot;mirror&quot;')"/>
        <xsl:value-of select="jcs:sleep(3,000)"/>
        <xsl:value-of select="local:pfe-push($connection,'set jbcm slot 6')"/>
        <xsl:value-of select="jcs:sleep(3,000)"/>
        <xsl:value-of select="local:pfe-push($connection,'set jbcm command &quot;mirror&quot;')"/>
        <xsl:value-of select="jcs:sleep(3,000)"/>
      </output>
      </xsl:otherwise>
    </xsl:choose>
    
 
    
  
 
    </op-script-results> 
  </xsl:template>

</xsl:stylesheet>
